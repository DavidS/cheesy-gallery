# Cache Mechanism Analysis (2026-05-11)

How `cheesy-gallery` 1.2.0 caches work, how they sit on top of (and
sometimes around) Jekyll 4.4.1's own caching, where invalidation
happens, and what happens once you put a `git-annex` worktree
underneath it all.

> **Note for readers of v1.2+:** this doc was originally written for the
> RMagick-backed v1.1.x. Layers A–C and the invalidation model are
> unchanged under the libvips backend. **Layer D** has been rewritten
> below to describe libvips' operation cache instead of RMagick's
> decoded pixel cache. Code snippets that mention `Magick::Image.ping`
> or `Magick::ImageList.new` reflect the historical implementation;
> the current call sites are `Vips::Image.new_from_file` (replacing
> the ping) and `Vips::Image.thumbnail` (replacing the decode+resize
> pair, now fused). The cache-spec spy targets are updated to match —
> see `spec/cheesy/cache_spec.rb`.

## TL;DR

- The plugin maintains **two named `Jekyll::Cache` instances** that
  persist across builds in `<source>/.jekyll-cache/Jekyll/Cache/`:
  `CheesyGallery::Render` (boolean per destination path) and
  `CheesyGallery::Geometry` (resized dimensions per source).
- It also leans on Jekyll's per-process `StaticFile.mtimes` hash and on
  the **destination file existing on disk with the correct mtime** —
  the source mtime is copied onto every rendered file via `File.utime`,
  which is what makes the next build's `modified?` check return false.
- There are therefore **four cache layers**, in order of precedence
  inside `BaseImageFile#write`: (1) destination-exists + mtime-match
  (Jekyll's native check, but cold on a fresh process), (2) the
  `Render` named cache, (3) the geometry cache (queried once at
  generator time, never re-checked at write time), and (4) RMagick's
  own internal disk cache for the decoded source.
- `--disable-disk-cache` is honoured by accident (the underlying
  `Jekyll::Cache` short-circuits), and the `mtimes` hash is
  per-subclass — `ImageFile.mtimes` and `ImageThumb.mtimes` are
  different hashes, but the two `ImageThumb` variants (`*_thumb.jpg`
  and `*_index.jpg`) for the same source share theirs, with subtle
  knock-on effects under scenario 7. See §5.
- `_config.yml` edits *do* invalidate both caches, but only because
  Jekyll calls `Jekyll::Cache.clear_if_config_changed` from
  `Site#process` and that does an indiscriminate
  `FileUtils.rm_rf(cache_dir)`. Any change to any config value
  triggers a full rebuild.
- **Run-to-run** (§3): the in-memory layers (A and the in-process
  half of B/C) die with the process, so a cold `jekyll build` re-loads
  Layer B and C from `.jekyll-cache/` and never hits Layer A on the
  first pass. The Render cache key is **just the destination path**,
  which means *editing a source file in place does not invalidate
  Layer B* — `jekyll clean` is required after edits. Under `--watch`
  the same staleness propagates further because Layer A then caches
  the new source mtime and short-circuits subsequent cycles.
- With `git-annex`, the workdir entries are symlinks into
  `.git/annex/objects/`. The plugin's geometry cache keys off
  `File.realdirpath(path)` + `File.mtime`, which means the key is
  stable per-clone but **differs across machines** — important if you
  ever ship `.jekyll-cache` between hosts. Locked annex contents are
  read-only and immutable, so caches stay valid until the symlink
  itself is repointed.

## 1. The cache layers, in flight order

### 1.1 Layer A — `StaticFile.mtimes` + dest-on-disk

`Jekyll::StaticFile.mtimes` is a class-level Hash maintained by Jekyll:

```ruby
# jekyll v4.4.1, lib/jekyll/static_file.rb
class << self
  def mtimes
    @mtimes ||= {}
  end
end

def modified?
  self.class.mtimes[path] != mtime
end
```

The vanilla `StaticFile#write(dest)` short-circuits with
`return false if File.exist?(dest_path) && !modified?`. `cheesy-gallery`
keeps this check at the top of its override
(`base_image_file.rb:28-30`).

Two consequences are easy to miss:

1. **`@mtimes` is a class-instance variable**, not a class variable.
   Ruby does not inherit class-instance variables, so
   `ImageFile.mtimes` and `ImageThumb.mtimes` are **different hashes**.
   The `jekyll-api-review.md` §1.4 sentence to the contrary is
   imprecise: each subclass has its own `@mtimes`. In practice this
   doesn't hurt correctness — each subclass independently records the
   source mtime against the same source path key — but it does mean the
   commentary "the source path appears as the key whether we're
   writing the full-size image or its thumbnail" describes intent more
   than implementation.
2. **The hash is only populated *during* a build**. On a cold process
   start (the normal case for `jekyll build`), `mtimes` is empty, so
   `modified?` is always `true` on the first visit to any file.
   Layer A therefore does not save work on the *first* file of a build
   — its real job is to suppress redundant writes when `--watch`
   reruns the generator inside the same Ruby process.

So Layer A is effective for `jekyll serve --watch` (the in-process
loop) but not for `jekyll build` invoked fresh from the shell.

### 1.2 Layer B — `CheesyGallery::Render` named cache

Defined as a class variable in the base class:

```ruby
# lib/cheesy-gallery/base_image_file.rb:8
@@render_cache = Jekyll::Cache.new('CheesyGallery::Render')
```

Class **variables** (`@@`) *are* inherited (and shared across the
whole class hierarchy), which is what the `rubocop:disable Style/ClassVars`
comment "don't need to worry about inheritance here" is referring to.
So `BaseImageFile`, `ImageFile`, and `ImageThumb` all read and write
the **same** `Render` cache.

The cache is a boolean: the key is `"#{dest_path}-rendered"`, the
value is `true`. Its only purpose is to record that a particular
output file has been produced. The check sits *after* the Jekyll
`modified?` short-circuit:

```ruby
# lib/cheesy-gallery/base_image_file.rb:28-43
def write(dest)
  dest_path = destination(dest)
  return false if File.exist?(dest_path) && !modified?

  self.class.mtimes[path] = mtime

  return if @@render_cache.key?("#{dest_path}-rendered") && File.exist?(dest_path)

  FileUtils.mkdir_p(File.dirname(dest_path))
  FileUtils.rm(dest_path) if File.exist?(dest_path)
  copy_file(dest_path)

  @@render_cache["#{dest_path}-rendered"] = true

  true
end
```

`Jekyll::Cache#key?` looks in memory first, then on disk
(`.jekyll-cache/Jekyll/Cache/CheesyGallery--Render/<sha2[0..1]>/<sha2[2..]>`,
each entry a `Marshal.dump` of `true`). So **Layer B persists across
processes** — that is the layer that makes a second `jekyll build`
fast.

Why two checks? Layer A only fires when `mtimes` says the file is
unchanged *in this process*. Once `mtimes[path] = mtime` is set on
line 32, *subsequent* calls within the same build would see
`modified? == false`, but those subsequent calls don't really happen
in the same build for the same `dest_path`. The render cache is
therefore the **cross-process** equivalent of the mtime check — it
asserts "we have, at some point in the past, written this file to
this destination", and the `&& File.exist?(dest_path)` clause makes
sure the destination wasn't wiped (e.g. `jekyll clean`) since.

### 1.3 Layer C — `CheesyGallery::Geometry` named cache

Defined on `ImageFile`:

```ruby
# lib/cheesy-gallery/image_file.rb:9
@@geometry_cache = Jekyll::Cache.new('CheesyGallery::Geometry')
```

Populated at `ImageFile#initialize` — i.e. once per source image per
generator run, **regardless of whether the image needs to be
re-rendered**:

```ruby
# lib/cheesy-gallery/image_file.rb:17-29
realpath = File.realdirpath(path)
mtime = File.mtime(realpath)
geom = @@geometry_cache.getset("#{realpath}##{mtime}##{geometry_string}") do
  result = [100, 100]
  Jekyll.logger.debug 'Identifying:', path
  source = Magick::Image.ping(path).first
  source.change_geometry!(geometry_string) do |cols, rows, _img|
    result = [rows, cols]
  end
  source.destroy!
  result
end

data['height'] = geom[0]
data['width']  = geom[1]
```

Key points:

- Cache key is `"#{realpath}##{mtime}##{geometry_string}"`. **Symlinks
  are resolved** (`File.realdirpath`), and the **mtime is the
  realpath's mtime** — not the symlink's. The trailing `geometry_string`
  segment is the `max_size` value with `>` appended (shrink-only;
  see `image_file.rb` `geometry_string`), so changing `max_size` in
  `_config.yml` or upgrading to a release that changes the upscale
  policy invalidates entries naturally without needing a global cache
  wipe. Consequences for `git-annex` are in §6.
- Stored value is a 2-element array `[height, width]`. Tiny, so the
  disk-cache footprint is negligible even for 10 000 images.
- `getset` raises-and-rescues to detect cache misses (this is
  Jekyll::Cache idiom), so a corrupted on-disk entry will look like a
  miss and be silently recomputed — no manual recovery needed.
- The block runs `Magick::Image.ping`, which only reads JPEG metadata,
  not pixels — but it still has to load and decode that metadata. On a
  ten-thousand-photo site this is the second-biggest cost after actual
  resize, so the cache matters.

The geometry cache is **read at generator time** and **written
exactly once per first-seen `(realpath, mtime)` tuple**. There is no
re-read at write time — geometry is only used to populate
`data['height'] / data['width']`, which the layout uses for `<img
width=… height=…>` attributes. So Layer C does not gate I/O the way
Layer B does; it gates the per-image `Magick::Image.ping` call.

### 1.4 Layer D — libvips operation cache

When we *do* render (Layer A and B both miss), the subclass's
`process_and_write` runs `Vips::Image.thumbnail(source_path, ...)`
directly — libvips fuses decode + shrink-on-load + resize + (for
thumbnails) centre-crop into a single operation. The base class no
longer opens the source file itself; it just hands the source path
to the subclass:

```ruby
# base_image_file.rb
def copy_file(dest_path)
  Jekyll.logger.debug 'Rendering:', dest_path
  process_and_write(path, dest_path)
  unless File.symlink?(dest_path)
    File.utime(self.class.mtimes[path], self.class.mtimes[path], dest_path)
  end
  @@render_cache[render_cache_key(dest_path)] = true
end

# image_file.rb#process_and_write (full-size)
img = Vips::Image.thumbnail(source_path, target_w, height: target_h,
                            size: :down, crop: :none)
img.write_to_file(dest_path, Q: @quality, interlace: true,
                  strip: true, optimize_coding: true)
```

What used to be "decode the entire JPEG into a pixel buffer and then
resize" is now one library call that streams only the rows it needs
(JPEG shrink-on-load at 1/2, 1/4, or 1/8 inside the codec, plus
in-memory resize). There is **no separate decoded-pixel cache** to
size, and no `destroy!` lifecycle — the `Vips::Image` is freed by GC.

libvips does keep a small **operation cache** of recently-compiled
operation graphs (default ~100 entries; tunable via
`Vips.cache_set_max`). That's a process-local performance optimisation,
not a correctness-affecting cache; it's transparent to our code and
to the four-layer model above.

The generator's `collection.files.sort!` on `generator.rb:117` still
helps Layer D, but for a different reason now:

```ruby
# sort files by source path, so that we have better cache hits when
# reading from disk
# with more effort files could share the Magick::ImageList instance,
# but destroying those at the right time to stay within Magick's cache
# policy would be awkward at best
collection.files.sort! { |a, b| a.path <=> b.path }
```

Sorting by source path keeps the full-size variant and its thumb(s)
adjacent in iteration order. Under libvips this benefits **OS page
cache locality** (each `Vips::Image.thumbnail` re-opens the file; the
JPEG bytes are warm from the previous variant's open) and gives the
libvips operation cache a better chance of reusing a previously-
compiled graph. The TODO in the comment is now obsolete: there's no
`ImageList` instance to share, because there's no separate decode
step.

This is the cache layer most affected by the choice of source-image
storage (local FS vs. `git-annex`-resolved symlink vs. networked
FS) — see §6.

## 2. End-to-end timeline of a build

The four layers interleave roughly like this. **G** = generator
phase, **W** = write phase.

```
G  Generator#generate
G    foreach collection marked cheesy-gallery
G      foreach JPG in collection.files
G        ImageFile.new
G          ─ Layer C: geometry_cache.getset("#{realpath}##{mtime}##{geometry_string}")
G          ─ on miss: Magick::Image.ping → change_geometry! → destroy!
G        ImageThumb.new                          # no cache touched here
G      collection.files.sort!(path)              # primes Layer D ordering
W  Site#write
W    foreach static_file
W      StaticFile#write(dest)  → BaseImageFile#write
W        ─ Layer A: File.exist? && !modified?   → bail
W        mtimes[path] = mtime
W        ─ Layer B: render_cache.key? && File.exist? → bail
W        FileUtils.mkdir_p / rm
W        copy_file(dest_path)
W          ─ Layer D: Magick::ImageList.new(path)
W          ─ process_and_write (resize / fill / strip / write)
W          ─ source.destroy!
W          ─ File.utime(source_mtime, source_mtime, dest_path)
W        render_cache["#{dest_path}-rendered"] = true
```

The `File.utime(source_mtime, source_mtime, dest_path)` step on line
60 of `base_image_file.rb` is what makes the *next* build's Layer A
short-circuit fire: `File.exist?(dest_path)` is true, and the dest's
mtime now equals the source mtime that will be re-set into
`mtimes[path]` on the next pass. (See §4 for why this isn't quite
enough on its own.)

## 3. Run-to-run behaviour

The four layers above describe *one* build. Most of what makes
`cheesy-gallery` feel fast — or stale — is what happens between
builds.

### 3.1 What survives a process exit

| State                                              | Lives in     | Cleared by                          |
|----------------------------------------------------|--------------|-------------------------------------|
| `StaticFile.mtimes` (per-subclass class-ivar)      | Process RAM  | Process exit                        |
| `Jekyll::Cache.base_cache` in-memory hashes        | Process RAM  | Process exit                        |
| `.jekyll-cache/Jekyll/Cache/CheesyGallery--Render`| Disk         | `jekyll clean`, `rm -rf .jekyll-cache` |
| `.jekyll-cache/Jekyll/Cache/CheesyGallery--Geometry`| Disk       | `jekyll clean`, `rm -rf .jekyll-cache` |
| `_site/<rendered files>` (utime-stamped)           | Disk         | `jekyll clean`, `rm -rf _site`      |

The two volatile rows (RAM) are why a cold `jekyll build` cannot hit
Layer A on the *first* visit to any file: there is no in-memory state
left to consult. Layer B and Layer C survive because they are
serialised to disk; the rendered file in `_site/` survives for the
same reason.

### 3.2 What `.jekyll-cache/` looks like between builds

Each named cache is a directory tree of `Marshal.dump`-encoded files,
keyed by SHA2 of the cache key:

```
.jekyll-cache/Jekyll/Cache/
├── CheesyGallery--Geometry/
│   ├── 9f/
│   │   └── 23c8b1d2e4f6…   # Marshal.dump([1080, 1920])
│   └── …                   # one entry per (realpath#mtime#geometry_string)
└── CheesyGallery--Render/
    ├── 7e/
    │   └── 4d8f2a1c…        # Marshal.dump(true)
    └── …                   # one entry per dest_path
```

For a gallery of N source images with M sub-galleries that emit an
index thumbnail, expect roughly **N** Geometry entries + **2N + M**
Render entries (full-size, `*_thumb.jpg`, and each gallery's
`*_index.jpg`). Geometry blobs are ~30 bytes each; Render blobs are
the Marshal encoding of `true`, around 10 bytes. Total disk footprint
is small even at 100 000 images (~ 5 MB), but the **file count**
matters on slow filesystems; SHA2-prefixed bucket directories cap
fanout at 256.

Marshal format is stable across Ruby patch and minor versions; a
Ruby major-version bump is the only realistic way for old entries to
fail to deserialise. `Jekyll::Cache#getset` rescues `StandardError`,
so a corrupted blob is silently recomputed and rewritten on the next
build — no manual recovery needed.

Both cache keys embed **absolute paths** (`dest_path` for Render,
`realdirpath(path)` for Geometry), so `.jekyll-cache/` is not portable
across machines or even across `--destination` choices on the same
machine; see §3.4.

### 3.3 Path through `write` in seven common scenarios

For each scenario, the trace below assumes a fresh `jekyll build`
process (the `--watch` case is treated separately as scenario 8).

1. **Cold build, first ever.** No `.jekyll-cache/`, no `_site/`.
   - Layer A: miss (`mtimes` empty).
   - Layer B: miss (no entry on disk).
   - Layer C: miss (no entry on disk). `Magick::Image.ping` runs for
     every source.
   - `copy_file` runs for every variant.
   - After: `.jekyll-cache/` and `_site/` populated; dest mtimes
     match source mtimes via `File.utime`.

2. **Warm build, no source changes.**
   - Layer A: miss on every file (cold mtimes hash).
   - Layer B: hit. `key?` falls through to the on-disk file,
     `Marshal.load` deserialises `true`, in-memory hash populated.
     `File.exist?(dest_path)` is true. `write` returns `nil` —
     skipped.
   - Layer C: hit on every source. `getset` deserialises the cached
     `[h, w]` tuple. No `Magick::Image.ping` runs.
   - Net work: one `File.stat` and one disk `key?` per dest (cheap),
     one `File.mtime` + disk lookup per source. No RMagick activity
     at all.

3. **Warm build, one new photo added.**
   - The new source: cold path (ping + render full + render thumb,
     plus a gallery-thumb re-render if the new file became the
     gallery's `thumbnail.jpg` or first-by-name image).
   - Everything else: as in scenario 2.

4. **Warm build, source photo edited in place (or annex symlink
   repointed to a new object).** The destination filename is
   unchanged.
   - `File.stat(source).mtime` is now newer than the dest's `utime`
     stamp.
   - Layer A: miss. `mtimes` is empty *and* `modified?` is true
     (new source mtime ≠ nil).
   - `mtimes[path] = new_mtime`.
   - Layer B: **hit**. The Render cache key is `dest_path` only.
     `File.exist?(dest_path)` is true (we never deleted it).
     `write` returns `nil` — **skipped**.
   - **Result: the output is stale until manually invalidated.**
     Vanilla `Jekyll::StaticFile#write` would fall through to
     `copy_file` here (the mtime check fails so it copies the new
     content); the plugin's render-cache short-circuit suppresses
     that fallthrough. This is a real bug — call it the
     "Layer-B-shadows-Layer-A" gap — and is mentioned in
     §6.4 in its git-annex form. The fix is in §7.1: include source
     content/mtime in the Render cache key.
   - Workaround today: `jekyll clean`, or
     `rm .jekyll-cache/Jekyll/Cache/CheesyGallery--Render` after an
     edit.

5. **After `jekyll clean`.** Both `.jekyll-cache/` and `_site/`
   removed. Reduces to scenario 1.

6. **After `rm -rf _site/`** (cache kept).
   - Layer A: miss (dest doesn't exist; the
     `File.exist?(dest_path) && !modified?` is false on the first
     conjunct).
   - Layer B: `key?` hits on disk → loaded → `true`. But the second
     conjunct `File.exist?(dest_path)` is false. So the guard
     evaluates to false and `write` falls through to `copy_file`.
   - Layer C: hit. Geometry cache is fully intact, no pings.
   - Net work: full re-render, but no `Magick::Image.ping` calls.
     This is the "rebuild without RMagick metadata cost" path.

7. **After `rm -rf .jekyll-cache/`** (`_site/` kept).
   - Layer A: miss (cold mtimes). But `File.exist?(dest_path) &&
     !modified?` is `true && false` = false — falls through.
   - Layer B: `key?` returns false (no on-disk entry). Falls through.
   - Layer C: miss. Every source is re-pinged.
   - Net work: full re-ping + re-render for **`N` full-size + `N`
     thumbs** = `2N` decodes — *not* `2N + M` (M = gallery thumbs).
     The per-image `*_thumb.jpg` write sets
     `ImageThumb.mtimes[source_path] = mtime`; when the
     gallery-index `*_index.jpg` for the same source then runs, its
     destination still exists (we kept `_site/`), `mtimes[source]`
     is the matching `mtime`, so `File.exist?(dest_path) &&
     !modified?` is true and Layer A short-circuits *despite Layer B
     having no cached entry for it*. This is benign: the
     `_index.jpg` on disk really is the right content. But it is a
     surprising bypass and is the reason the matching scenario in
     `spec/cheesy/cache_spec.rb` asserts `N*2`, not `N*2 + M`,
     decodes.
   - This path is strictly worse than scenario 6, because the kept
     `_site/` buys nothing for the full-size and per-image thumbs.
     The lesson: cache `.jekyll-cache/` in CI before caching
     `_site/`.

8. **`jekyll serve --watch`** (same process across many cycles).
   - Cycle 1: as scenario 1 or 2 depending on prior state.
   - Cycle 2+: `mtimes` is now populated from cycle 1's writes.
     `modified?` is `false` for unchanged files → Layer A fires and
     `write` returns `false` early. This is much faster than the
     `key?`-on-disk path that cold builds take.
   - **The Layer-B-shadows-Layer-A bug from scenario 4 is *worse*
     under `--watch`**: after the first write of the edited file
     (which is still skipped by Layer B), `mtimes[path]` is set to
     the new source mtime. On the next watch cycle, Layer A
     short-circuits the file out even *before* reaching Layer B —
     and stays stale until the process is restarted or the cache is
     cleared.

### 3.4 CI cache strategy

Three reasonable CI cache configurations, in decreasing order of
effectiveness:

- **Save and restore both `.jekyll-cache/` and `_site/`.** Maximum
  hit rate. On a no-source-change run, scenario 2 applies: no
  RMagick work at all. Caveat: `dest_path` is absolute, so the CI
  workspace path must be stable across runs. GitHub Actions hosted
  runners always check out under
  `/home/runner/work/<repo>/<repo>/`, so this is naturally stable;
  self-hosted runners with ephemeral working directories will not
  hit anything.
- **Save and restore `.jekyll-cache/` only.** Scenario 6 applies on
  every run: full re-render, but no geometry pings. Useful when
  `_site/` is too large to cache or you publish a fresh build
  artefact every run anyway.
- **Save and restore `_site/` only.** Scenario 7 applies — full
  re-render *and* full re-ping. Don't bother; the saved `_site/`
  buys nothing on a cold-process cold-cache build.

A subtler note: because the keys embed absolute paths, switching the
build between two parallel checkouts of the same repo
(`/home/user/checkout-a/` and `/home/user/checkout-b/`) gives each
its own cache. That's fine, just not surprising.

### 3.5 Concurrency between processes

`Jekyll::Cache#[]=` writes via `Marshal.dump` to a path computed from
SHA2 of the key; there is no file locking. Two simultaneous
`jekyll build` processes pointing at the same `.jekyll-cache/`
directory can interleave writes for the same key and leave a
half-Marshalled file on disk. For the Geometry cache the next read
via `getset` rescues the `StandardError` from `Marshal.load`, treats
the entry as a miss, recomputes, and rewrites — so the corruption is
self-healing, but the recompute cost (a full `Magick::Image.ping`)
is paid. **The Render cache is not self-healing**: its check uses
`Jekyll::Cache#key?`, which only inspects `File.file?` and
`File.readable?` and never deserialises the blob. A corrupt-but-
present Render-cache entry therefore still suppresses re-render.
Don't run parallel builds against a shared cache; see
`spec/cheesy/cache_spec.rb` "Marshal corruption" examples for both
behaviours.

### 3.6 Verification: how each scenario is tested

Each of the eight scenarios above (and the related implementation
details in §1, §4-§6) is exercised by `spec/cheesy/cache_spec.rb`.
The strategy is:

- **`Magick::Image.ping`** is the only RMagick call inside the
  Geometry-cache `getset` block — so spying on it via
  `allow(Magick::Image).to receive(:ping).and_wrap_original` and
  counting calls is a direct measure of Layer C participation. Zero
  pings on a warm build proves Layer C hit on every source.
- **`Magick::ImageList.new`** is the first call inside
  `BaseImageFile#copy_file`, which is reached only when Layer A and
  Layer B both miss. Counting calls is a direct measure of *render*
  participation. Zero decodes proves the file was skipped (by either
  Layer A or Layer B), and the corroborating `File.mtime(dest)`
  before/after comparison pins down which one.
- **Cold-process simulation between builds.** The suite calls a
  `simulate_cold_process!` helper that resets the in-memory state a
  fresh Ruby process would have lost — `StaticFile.mtimes` (per
  subclass), the inner `@cache` hash on each named `Jekyll::Cache`
  instance, and the `@base_dir` memoisation on those instances —
  without touching `.jekyll-cache/` or `_site/`. That is the
  smallest possible "second build" — i.e. proves the cache survived
  the simulated restart, not just that the in-process state did.
- **`File.exist?` on `.jekyll-cache/Jekyll/Cache/CheesyGallery--…/`
  blobs** confirms that the disk side of each named cache populates
  on the first build and remains after the simulated restart. The
  Render cache key-set inspection (`@cache.keys`) directly verifies
  the key shape (`"<dest_path>#<mtime>#<discriminator>-rendered"`
  for `ImageFile`, with the geometry string as the discriminator;
  `"<dest_path>#<mtime>-rendered"` for `ImageThumb`, where the
  discriminator is currently empty) and the Geometry key shape
  (`"<realpath>#<mtime>#<geometry_string>"`).

The scenario-to-test mapping:

| Scenario              | Spec describe                                    | Cache-participation signal       |
|-----------------------|--------------------------------------------------|----------------------------------|
| §3.3 #1 cold          | `scenario 1: cold first build`                   | ping=N, decode=2N+M              |
| §3.3 #2 warm          | `scenario 2: warm second build, no source changes` | ping=0, decode=0; mtimes unchanged |
| §3.3 #3 +new photo    | `scenario 3: warm build with one new photo`      | ping=1, decode=2                 |
| §3.3 #4 edited source | `scenario 4: source edited in place, …`          | regression (decode=0); pending  (decode>0)  |
| §3.3 #5 after clean   | `scenario 5: after jekyll clean`                 | ping=N, decode=2N+M (= scenario 1) |
| §3.3 #6 rm _site/     | `scenario 6: rm -rf _site/ only (cache kept)`    | ping=0, decode=2N+M              |
| §3.3 #7 rm cache      | `scenario 7: rm -rf .jekyll-cache/ only (_site kept)` | ping=N, decode=2N (Layer A bypass) |
| §3.3 #8 --watch       | `scenario 8: in-process re-build (jekyll serve --watch)` | ping=0, decode=0 via Layer A   |
| §4 config edit        | `Jekyll wipes our caches when _config.yml changes` | ping=N after edit               |
| §5.1 symlinks         | `path vs realpath via symlinked source`          | Geometry key contains realpath   |
| §5.5 thumbs           | `ImageThumb does not consult the Geometry cache` | ping=N regardless of thumb count |
| §1.1 mtimes split     | `StaticFile.mtimes is per-subclass`              | `ImageFile.mtimes.object_id != ImageThumb.mtimes.object_id` |
| §3.5 corruption       | `Marshal corruption in a …`                     | Geometry self-heals; Render doesn't |

The §3.3 scenario 4 entry is the bug `pending`-marked in the spec:
the assertion is the *desired* behaviour (`decode > 0`), so the
test stays red as a known bug until §7.1's fix lands; a sibling
regression test asserts the *current* (buggy) behaviour explicitly
so the fix is a deliberate suite change.

## 4. What actually invalidates each layer

| Layer | Invalidated by                                                                                            | Survives `jekyll clean`? | Survives `_config.yml` edit? |
|-------|-----------------------------------------------------------------------------------------------------------|--------------------------|------------------------------|
| A — `mtimes` hash             | New process. Anything that resets the class-instance variable.                  | n/a (in-memory)          | n/a                          |
| B — `Render` named cache       | `jekyll clean`. `File.exist?(dest_path) == false`. **Any** `_config.yml` edit (via `clear_if_config_changed`). | **No**                   | **No** (whole cache dir wiped) |
| C — `Geometry` named cache     | `jekyll clean`. Source `realpath` or `mtime` change. **Any** `_config.yml` edit.                          | **No**                   | **No** (same)                |
| D — RMagick decode             | Per-process; freed on `destroy!`.                                              | n/a                      | n/a                          |

The earlier draft of this table claimed `_config.yml` edits leave our
caches stale. That turns out to be wrong; verified by
`spec/cheesy/cache_spec.rb` ("§4: invalidation behaviour"). Jekyll
calls `Jekyll::Cache.clear_if_config_changed(site.config)` from
`Site#process` (jekyll 4.4.1 `lib/jekyll/site.rb:118`), and that
class-level `clear` does `FileUtils.rm_rf(Jekyll::Cache.cache_dir)` —
which removes the *entire* `<source>/.jekyll-cache/Jekyll/Cache/`
subtree, including our named caches. It also `Hash#clear`s every
in-memory `Jekyll::Cache.base_cache` entry. The upshot:

- Any change to `_config.yml` that alters its `Hash#inspect`
  representation — a typo fix, a `quality:` change, a `title:` edit,
  *anything* — nukes both our caches. This is generous (no staleness
  bugs) and wasteful (a one-character fix re-pings and re-renders
  every photo).
- The fingerprint Jekyll stores is `config.inspect` (a Ruby string).
  Whitespace and ordering of YAML keys don't matter (YAML→Hash
  normalises), but adding/removing/touching *any* key value does.

Two real gaps remain, both already flagged in
`docs/jekyll-api-review.md` §1.6:

1. **`--disable-disk-cache` is ignored.** Jekyll's CLI calls
   `Jekyll::Cache.disable_disk_cache!`, which sets a class flag that
   *Jekyll-owned* caches consult. The per-instance code paths
   (`base_image_file.rb:34`, `image_file.rb:19`) call `key?` /
   `getset` directly. Those methods *do* check the class flag, so
   reads bypass disk correctly — but writes via `cache[key] = value`
   *also* bypass disk in that case, so the layer just becomes
   in-memory. Functionally fine; behaviourally it means
   `--disable-disk-cache` works "by accident" rather than by design.
2. **Corrupted Render-cache blobs are not self-healing.** The
   Render cache check is `key? && File.exist?(dest_path)`, and
   `key?` only does `File.file? && File.readable?` — it never tries
   to deserialise. A corrupt (or zero-byte, or truncated) blob is
   indistinguishable from a valid one and still suppresses the
   re-render. The Geometry cache is unaffected, because it goes
   through `getset`, which `rescue StandardError`s a `Marshal.load`
   failure and recomputes. Verified by the two
   `Marshal corruption in a … cache blob` examples in
   `spec/cheesy/cache_spec.rb`. Workaround: `rm -rf .jekyll-cache/`
   on suspicion. Long-term fix: have BaseImageFile go through
   `getset` instead of `key?`, or store a checksum alongside the
   boolean.

And one more subtle behaviour worth knowing:

3. **`ImageThumb.mtimes` is shared by per-image and gallery-index
   thumbs of the same source.** Both `*_thumb.jpg` and `*_index.jpg`
   are `ImageThumb` instances; their class-instance `@mtimes` hash
   is therefore the same. When the first one's `write` succeeds it
   sets `mtimes[source_path] = mtime`. If both destinations already
   exist on disk (the "kept `_site/`" case), the second thumb's
   Layer A short-circuit fires (`File.exist?(dest_path) &&
   !modified?` → true && true → return false) and the second
   variant is silently skipped — *even though the Render cache is
   empty*. This is benign when the dest is correct (it really is
   already rendered, scenarios 2 and 7), but pathological under the
   §3.3 scenario 4 source-edit bug, because Layer A then short-
   circuits on a *stale* dest. Pinned down by scenario 7 in
   `spec/cheesy/cache_spec.rb` (expected decodes = `N*2`, not
   `N*2+1`, despite the `_index.jpg` blob having been wiped from
   disk).

A fourth, mostly-cosmetic gap:

4. **Different `--destination` directories double the cache
   footprint until config changes invalidate it.** The Render cache
   key embeds the absolute `dest_path`. Two builds with different
   destinations would share no Render-cache entries — but
   destination is in `config`, so changing it also triggers
   `clear_if_config_changed`. Net: the doubling only persists if you
   somehow run two builds with *different* destinations and
   *identical* config (e.g. via the `--destination` CLI flag, which
   bypasses `_config.yml`). Rare.

## 5. Other implementation details worth knowing

### 5.1 `path` vs. `realpath`

`BaseImageFile#path` is overridden to return the *source file's*
declared path (`@source_file.path`) rather than letting
`Jekyll::StaticFile#path` reconstruct one from `@base + @dir + @name`.
That's how `mtimes[path] = mtime` agrees with `File.mtime` later —
both speak the same path.

`ImageFile#initialize`, separately, calls `File.realdirpath(path)`
specifically to dereference symlinks before using the result as the
geometry cache key. This is the only place in the plugin that resolves
symlinks. Layer A (mtimes), Layer B (render cache, keyed off
`dest_path`), and `path` itself all stay symbolic.

### 5.2 Layer A fires only on warm processes

As noted in §1.1, `StaticFile.mtimes` is populated by `#write` itself,
so on a cold `jekyll build` it is empty when the first static file
is processed. The Layer A check (`File.exist?(dest_path) && !modified?`)
therefore *always* takes the slow path on the first invocation —
which is fine, because Layer B catches it.

For `jekyll serve --watch` the picture is different: the same Ruby
process re-enters `Site#process` whenever a watched file changes,
`mtimes` carries forward, and Layer A starts being the dominant
short-circuit. This is also why the `--watch` story is reasonably
snappy despite the plugin not implementing `--incremental`.

### 5.3 The destination-utime trick

`copy_file` finishes with:

```ruby
unless File.symlink?(dest_path)
  File.utime(self.class.mtimes[@source_file.path],
             self.class.mtimes[@source_file.path],
             dest_path)
end
```

This forcibly sets the destination's atime+mtime to match the source.
Two reasons:

- It's what makes `File.exist?(dest_path) && !modified?` come out
  *true* on the next build: the next pass sets
  `mtimes[path] = File.mtime(source).to_i` early in the iteration,
  then `modified?` compares `mtimes[path] != mtime` — and since `mtime`
  is computed from `File.stat(path).mtime` (the *source*),
  `mtimes[path]` and `mtime` are equal — `modified?` is `false`, and
  Layer A fires.
- The `File.symlink?` guard prevents touching the underlying file
  when the dest happens to be a symlink (`File.utime` follows
  symlinks by default). The plugin never emits symlinked output, so
  this is mostly defensive.

### 5.4 The redundant `FileUtils.rm`

Line 37 (`FileUtils.rm(dest_path) if File.exist?(dest_path)`)
duplicates what Jekyll's own `StaticFile#write` does and the comment
on line 26-27 (`Inject cache here to override default
delete-before-copy behaviour`) says the *whole point* is to avoid the
delete. The remaining `rm` is then defensive for the unusual case
where the render cache thinks a file is already on disk but Layer B's
`&& File.exist?(dest_path)` guard somehow missed (race, manual `rm`
between cache-write and now). Net effect: harmless if the file is
already gone, costs one syscall otherwise.

### 5.5 `ImageThumb` never touches geometry cache

`ImageThumb` resizes-to-fill to fixed pixel dimensions
(`@height`, `@width`) — no aspect-ratio math, so no `change_geometry!`,
so no need to memoise anything. Layer C is `ImageFile`-only.

## 6. Source images on `git-annex`

The cheesy.at site keeps its master archive on `git-annex`. The
relevant question is: when `git annex get` populates objects in
`.git/annex/objects/`, and the workdir contains symlinks pointing
into those objects, do the four cache layers behave well?

### 6.1 What the workdir looks like

By default (`git annex add`, no `unlock`), each tracked image is a
**symlink**:

```
_galleries/2024-greece/IMG_2391.jpg
  → ../../.git/annex/objects/QX/97/SHA256E-s4193241--abc123…/SHA256E-s4193241--abc123…
```

The annex object itself is `chmod 444` (read-only), owned by the user,
with an mtime set at the time the object was placed in the local
object store (usually `git annex add` / `git annex get`).

Variations:

- **Adjusted branches / v7 / v8 worktree-modes** — workdir entries
  are real files (hardlinks or copies) and the annex tracks pointer
  files in the index. The on-disk file looks like a normal JPEG to
  Jekyll. From the plugin's perspective this is the easy case.
- **`git annex unlock`** — single-file equivalent of the above. The
  file becomes a regular writable copy in the workdir.
- **Locked symlink (default)** — the case we focus on below.

### 6.2 Layer-by-layer interaction

**Layer A (`mtimes` + dest-on-disk).** `BaseImageFile#path` returns
the symlink path. `Jekyll::StaticFile#modified_time` is
`File.stat(path).mtime` — `File.stat` follows symlinks, so it reports
the annex object's mtime. That value is stable for as long as the
symlink points to the same key. Layer A is therefore happy: once we
write the dest with `File.utime(source_mtime, …)`, the next build's
mtime comparison succeeds.

**Layer B (`Render` named cache).** Keyed on `dest_path`. Independent
of how the source is stored. Works identically with or without
git-annex. The disk cache itself lives under `.jekyll-cache/`, which
is **not** annex-tracked (it's a build artefact); CI tends to write
it from scratch unless explicitly cached as a CI artefact.

**Layer C (`Geometry` named cache).** Keyed on `File.realdirpath(path) +
"#" + File.mtime(realpath)`. With locked annex:

- `realpath` resolves to
  `…/.git/annex/objects/QX/97/SHA256E-s…--…/SHA256E-s…--…`. The hash
  portion encodes the file's content (`SHA256E` keys), so the
  realpath is **content-addressed**. Two clones of the same repo,
  both with the file present, see the **same path suffix** but
  prefixed with the local checkout root — i.e. different absolute
  realpaths.
- `mtime` of the annex object is set when the object is placed in
  the object store. It is **not** the original photo's EXIF time, nor
  the `git add` time, nor `now` — it's whatever the kernel saw when
  `git annex add` / `get` ran. In practice it is stable
  per-clone-per-`get`.

Consequences:

1. **The geometry cache is per-clone**, not per-content. Shipping a
   pre-warmed `.jekyll-cache` from CI to a developer's laptop will
   miss every entry — the realpath prefix differs. Fine, just don't
   expect that to work as a speed-up.
2. **Locked annex contents are immutable** while their key is the
   same. Once the geometry for a given object's `(realpath, mtime)`
   is cached, *no edit* will invalidate it unless the symlink is
   re-pointed (which happens only if the file's content changes and a
   new annex key is created). So the geometry cache is essentially
   "warm forever" for a stable photo archive. Good outcome.
3. **A fresh `git annex get`** of a previously-dropped object writes
   a new file with a new mtime. That changes the cache key and
   invalidates Layer C for that source. Cost: one
   `Magick::Image.ping` per re-fetched image on the next build.
   Trivial.
4. **The realpath includes the SHA256E key** in its filename, so even
   if the symlink is repointed (e.g. content updated), the key
   suffix changes — the *old* geometry entry is orphaned, the *new*
   one is cleanly cached. No risk of returning stale geometry for
   a swapped-out object.

**Layer D (RMagick decode).** Reads the annex object directly via
the symlink. Two notes:

- **Read-only source.** RMagick reads, never writes. The default
  444 permissions on the annex object are fine.
- **`MAGICK_DISK_LIMIT` may spill to disk.** That spill goes to
  `MAGICK_TEMPORARY_PATH` (usually `/tmp`), *not* to the annex
  object's directory, so there is no risk of corrupting the
  immutable object.

### 6.3 Things that go subtly wrong with `git-annex`

1. **Missing objects = build failure.** A locked symlink with no
   annex object present is a *dangling* symlink. `File.exist?(path)`
   returns `false`, `File.mtime(path)` raises `Errno::ENOENT`. The
   generator will crash during `ImageFile#initialize` (the
   `File.mtime(realpath)` line). CI must run `git annex get .`
   (or `git annex get _galleries/`) before `jekyll build`.
2. **`File.realdirpath` cost.** Once per source per build. Resolves
   one symlink, one `stat`. Microseconds. Not a concern.
3. **`utime` on the destination doesn't affect the source.**
   `File.utime` on `dest_path` rewrites the dest; the source remains
   read-only annex object. Confirmed: no risk of mutating the annex
   store.
4. **`jekyll clean` does NOT touch annex objects.** Layer B and C
   live under `.jekyll-cache/`; the destination tree lives under
   `_site/`. Both are safe to delete and unrelated to annex
   state. (Worth flagging because some users worry.)
5. **Mtime granularity.** Some filesystems (FAT, older NFS) coarsen
   mtimes to 1-second or 2-second precision. Across hosts in CI this
   can collide with the geometry cache key's mtime component when an
   annex object is re-fetched within the same second as a previous
   record. Result: a cache *hit* on a (nominally) different object.
   This isn't really a bug — the realpath also includes the SHA256E
   key, so content-distinct objects have content-distinct paths, and
   the (path, mtime) tuple still uniquely identifies the object.
6. **WORM / non-content-addressing backends.** If someone configures
   annex with the `WORM` backend instead of `SHA256E`, the annex key
   no longer encodes content. Re-`add`ing the same file under WORM
   produces a new key based on filename+size+mtime; the realpath
   changes; Layer C re-fingerprints. Slightly more cache churn, but
   no incorrectness.
7. **Concurrent `git annex sync` during a build.** If a sync swaps
   the symlink target mid-build (very narrow window between
   `ImageFile#initialize` and `BaseImageFile#write`), the geometry
   cached in Layer C reflects the *old* content while the rendered
   image reflects the *new* one. Easy to avoid — don't run annex
   operations during a build.

### 6.4 Recommended workflow

For a `git-annex`-backed gallery archive consumed by `cheesy-gallery`:

- **Locked annex (default) is the right choice.** It gives the
  geometry cache and the render cache their best behaviour:
  immutable content, stable realpath per-clone, mtime that only
  changes on re-`get`.
- **CI**: `git annex init`, `git annex get _galleries/` (or whatever
  paths the collection covers), then `bundle exec jekyll build`.
  Cache `.jekyll-cache/` between CI runs *only if* the CI workspace
  is preserved across runs (same realpath prefix); otherwise the
  cache will miss anyway and incur disk-write cost without disk-read
  benefit.
- **Locally**: don't `git annex drop` files you plan to render. The
  next `jekyll build` will fail until you `git annex get` them
  back.
- **Authoring**: if you need to *edit* a photo (rotate, crop,
  re-export), do it in your editor against the original, then
  `git annex add` the new file. The new annex key means a new
  realpath, which transparently busts Layer C; combined with the
  source mtime change, Layer A also invalidates correctly; and
  because the dest mtime no longer matches, Layer B's render-cache
  hit is overridden by the destination utime check on the *next*
  build (the cache says "rendered", but Layer A reports modified —
  Layer B is consulted, sees its entry, but `File.exist?(dest_path)
  && !modified?` from Layer A has already returned `false`, so we
  proceed to `mtimes[path] = mtime`, then check Layer B which
  says "rendered" — *and we skip re-render*). **This is a real
  invalidation gap**: the Render cache does not invalidate when the
  source changes, only when the destination disappears. With
  git-annex, edits change the source `realpath` (new key) but the
  *dest_path* string is unchanged, so Layer B still says "done".
  Workaround: `jekyll clean` after publishing an edit. Long-term
  fix: include the source mtime (or realpath suffix) in the
  Render cache key.

### 6.5 Summary table

| Concern                         | Locked annex symlink                  | Unlocked / adjusted file |
|---------------------------------|---------------------------------------|--------------------------|
| Source mtime stable?            | Yes (per-clone, per-`get`)            | Changes on edit          |
| Source realpath stable?         | Yes until content key changes         | Yes                      |
| Source is read-only?            | Yes (444)                             | No                       |
| Layer C cache portable across hosts? | No (realpath prefix differs)     | No (same reason)         |
| Layer C invalidates on edit?    | Yes (new annex key → new realpath)    | Yes (mtime changes)      |
| Layer B invalidates on edit?    | **No** — keyed on dest_path           | **No** — same gap        |
| Risk of mutating source?        | None                                  | None                     |
| Build needs `git annex get`?    | Yes                                   | No                       |

## 7. Concrete improvement opportunities

These build on `docs/jekyll-api-review.md` §3.1 but are specifically
cache-shaped.

1. **Make the `Render` cache key content-aware.** Either
   `"#{dest_path}##{File.mtime(@source_file.path).to_i}"` or include
   `File.realdirpath(path)` so that, when the annex key changes,
   the cache key changes too. This closes the §6.4 last-bullet hole
   and §3.3 scenario 4's Layer-B-shadows-Layer-A bug.
2. **Hook into `clear_if_config_changed`.** Call
   `Jekyll::Cache.clear_if_config_changed(site.config)` from
   `Generator#generate` (or, more selectively, include a digest of
   `collection.metadata.slice('max_size', 'quality',
   'image_thumbnail_size', 'gallery_thumbnail_size')` in the
   `Geometry` and `Render` cache keys). Prevents the §4 stale-cache
   gap after `max_size`/`quality` edits.
3. **Honour `--disable-disk-cache` explicitly.** Even though
   `Jekyll::Cache` already short-circuits disk I/O when the flag is
   set, calling `disk_cache_enabled?` before `getset` and falling
   back to "always recompute" makes the contract explicit and lets
   us skip the in-memory cache too if a user genuinely wants
   reproducible no-cache behaviour.
4. **Cap the geometry cache.** Today entries are never evicted.
   `.jekyll-cache/Jekyll/Cache/CheesyGallery--Geometry/` will keep
   growing across years of edits — each entry is ~50 bytes, so
   even 100 000 entries is ~5 MB, but the *file count* matters on
   slow filesystems (`fsync`-heavy SSDs, network shares). A
   periodic `Jekyll::Cache#clear` tied to `_config.yml`'s
   `clear_geometry_cache: true` would be enough.
5. **(Optional) Share `ImageThumb` and `ImageFile` mtime hashes.**
   Promote `mtimes` to a class variable in `BaseImageFile`
   (`@@mtimes`) — or, simpler, set
   `Jekyll::StaticFile.mtimes[path] = mtime` directly (the parent's
   `@mtimes`) so both subclasses share one hash and the
   `jekyll-api-review.md` §1.4 description becomes accurate.

## 8. References

- Plugin source: `lib/cheesy-gallery/base_image_file.rb`,
  `lib/cheesy-gallery/image_file.rb`,
  `lib/cheesy-gallery/image_thumb.rb`,
  `lib/cheesy-gallery/generator.rb`.
- Jekyll 4.4.1: [`lib/jekyll/cache.rb`](https://github.com/jekyll/jekyll/blob/v4.4.1/lib/jekyll/cache.rb),
  [`lib/jekyll/static_file.rb`](https://github.com/jekyll/jekyll/blob/v4.4.1/lib/jekyll/static_file.rb).
- Companion document: [`jekyll-api-review.md`](jekyll-api-review.md) —
  esp. §1.4 (StaticFile), §1.6 (Cache), §3.1 (tighten-as-is plan).
- `git-annex` background: [object storage layout](https://git-annex.branchable.com/internals/),
  [SHA256E key backend](https://git-annex.branchable.com/backends/),
  [locked vs unlocked content](https://git-annex.branchable.com/git-annex-unlock/).
