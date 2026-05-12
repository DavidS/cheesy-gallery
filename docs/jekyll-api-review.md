# Jekyll Plugin API Review (2026-05-10)

A survey of the current Jekyll plugin API surface (against Jekyll **4.4.1**,
released 2025-01-29 — the latest line; no 5.x exists yet), and a comparison
with the integration points that `cheesy-gallery` 1.1.1 currently uses. The
goal is to figure out which parts of the plugin can be simplified, which
should stay as they are, and what new options have appeared since the gem
was last released.

## TL;DR

- The plugin's overall shape — `Jekyll::Generator` subclass that injects
  `Jekyll::StaticFile` subclasses and a synthetic `Jekyll::Document` — is
  still the canonical way to do what `cheesy-gallery` does. Nothing in
  Jekyll 4.2 → 4.4 has obsoleted that pattern.
- There is **no first-class hook for static-file transforms**. The Hooks
  registry only knows the owners `:site`, `:pages`, `:posts`, `:documents`,
  `:clean` — not `:static_files`. So subclassing `StaticFile` and overriding
  `write` remains the only way to plug in RMagick rendering.
- Jekyll 4.3 changed *where the writer reads static files from*
  (`site.static_files` rather than `collection.files`), which silently
  broke the plugin's thumbnail output. That's already fixed on `main` in
  `9dd18c0`; see §1.2.
- The biggest realistic wins are: (1) switching to **libvips/ruby-vips** for
  ~10× faster thumbnail generation, (2) using `Jekyll::Cache.clear_if_config_changed`
  for automatic invalidation on `_config.yml` edits, (3) honouring
  `--disable-disk-cache`, and (4) optionally splitting the plugin into a
  thinner gallery-navigation generator + delegating image processing to
  `jekyll-picture-tag`.

## 1. Where Jekyll's plugin API stands today

### 1.1 Plugin types (unchanged since 4.0)

[Jekyll plugins](https://jekyllrb.com/docs/plugins/) still come in seven
flavours: **Generators, Converters, Commands, Tags, Filters, Hooks**, plus
**Themes**. No new top-level plugin type has been introduced in 4.x.

### 1.2 Hook registry (the only meaningful API growth area in 4.x)

Recognised owners and events as of Jekyll 4.4.1
(`lib/jekyll/hooks.rb`):

| Owner          | Events                                                                   |
|----------------|--------------------------------------------------------------------------|
| `:site`        | `:after_init`, `:after_reset`, `:post_read`, `:pre_render`, `:post_render`, `:post_write` |
| `:pages`       | `:post_init`, `:pre_render`, `:post_convert`, `:post_render`, `:post_write` |
| `:posts`       | (same as `:pages`)                                                       |
| `:documents`   | (same as `:pages`)                                                       |
| `:clean`       | `:on_obsolete`                                                           |

What's new since `cheesy-gallery` 1.1.1 was last cut:

- **4.2.0** — `:post_convert` (fires after Markdown→HTML conversion but
  before the layout wraps the content). Useful for transforming rendered
  HTML; not directly relevant to image rendering.
- **4.3.0** — `site.static_files` now also enumerates *collection* static
  files (#8961), and `Document#name` (the basename) is exposed to Liquid
  (#8761). The first is more than a layout-filtering convenience: as of
  4.3, `Collection#read` snapshots `collection.files` into
  `site.static_files` at *read* time, and `Site#each_site_file` writes
  from `site.static_files` rather than re-iterating each collection.
  Plugins (like this one) that mutate `collection.files` from inside a
  generator therefore have to mirror those mutations into
  `site.static_files`, otherwise the writer doesn't see them. This is
  the bug fixed on `main` in commit `9dd18c0` (`Sync site.static_files
  in generator; refresh fixture lock`).
- **4.4.0** — no plugin-API surface change; bumps min Ruby to 2.7, adds
  `csv`, `base64`, `json` to the runtime dep list.

What is **still missing**:

- No `:static_files` hook owner. There is no `:before_write` or
  `:on_static_file_write` event, which is exactly the seam
  `BaseImageFile#write` is filling by subclassing.
- No `:collections` hook owner — `Generator` remains the only place to
  rewrite a collection's contents.

### 1.3 `Jekyll::Generator`

Mostly identical to 4.0. Three things worth re-stating because the current
code uses (or could use) all of them:

- `priority :low | :high | :lowest | :highest` controls ordering between
  generators. The current generator does not declare a priority and runs
  at default. If we grow more generator-style features (e.g. a nav-only
  variant), give the image-processing generator `priority :low` so other
  generators see the documents *before* we wrap their files.
- Generators run *after* `:site, :post_read`, so anything you can do in a
  `Hooks.register :site, :post_read` block you can also do in a Generator.
  In other words, the post-read hook is a stylistic alternative to
  subclassing `Generator`, but does not unlock new capability.
- The `safe true` flag is required if we ever want the gem to work under
  `--safe` (i.e. on GitHub Pages without `unsafe`). The current code does
  not declare it; doing so is harmless and a good signal.

### 1.4 `Jekyll::StaticFile`

Source still looks essentially as the plugin's `BaseImageFile` describes.
The shape of `write(dest)` in 4.4.1:

1. Compute `destination(dest)`.
2. Bail out with `return false` if the dest exists and `!modified?`.
3. Update `self.class.mtimes[path]`.
4. `mkdir_p`, `rm_f`, `copy_file`.

Notable points for our subclass:

- `self.class.mtimes` is a class-level **instance** variable (`@mtimes`),
  so each subclass gets its own hash — `ImageFile.mtimes` and
  `ImageThumb.mtimes` are distinct objects. Verified by
  `spec/cheesy/cache_spec.rb` "§1.1: StaticFile.mtimes is per-subclass"
  and documented in `docs/cache-analysis.md` §1.1. The two `ImageThumb`
  variants (per-image `*_thumb.jpg` and per-gallery `*_index.jpg`) for
  the same source *do* share an entry, since they're both `ImageThumb`
  instances — see scenario 7 in `cache-analysis.md` §3.3 for the
  surprise this causes.
- There is still no `before_write` / `after_write` hook, so the only way
  to short-circuit copy and substitute RMagick rendering is to override
  `write` (current approach) or `copy_file` (slightly cleaner — see §3.1).
- 4.4.x respects `--disable-disk-cache`; `Jekyll::Cache.disable_disk_cache!`
  is invoked from the CLI when that flag is set. We should defer to that
  for our two named caches; today they ignore the flag.

### 1.5 `Jekyll::Document`

As of PR #415 (`d5133a6`) `GalleryIndex` overrides `read` directly
rather than the private `read_content`. The internal flow is
`read → merge_defaults → read_content → read_post_data`. Three mild
gotchas:

- `read_content` is technically a **private** method in 4.x; the
  earlier `read_content` override worked but was semi-internal. The
  override on `read` calls `merge_defaults` itself and sets
  `self.content` without calling `super`, because the synthetic doc
  has no backing file and `super` would `ENOENT` on `File.read(path)`.
- `data.default_proc` is set in `initialize` to fall through to
  `site.frontmatter_defaults`. That means setting `doc.data['layout']`
  *after* `read` (as the generator does on line 26) is fine, but if we
  ever want layout/title to come from `_defaults` we should *not* set it
  unconditionally — let the default_proc resolve it.
- `cleaned_relative_path`, `basename_without_ext`, and `relative_path`
  are all memoised getters; their semantics are unchanged. The generator's
  use of `e.basename_without_ext == 'index'` to find existing indices is
  stable.

### 1.6 `Jekyll::Cache`

Public surface in 4.4.1:

- `Jekyll::Cache.new(name)` — named cache, on-disk under `.jekyll-cache/Jekyll--Cache/<name>/<sha2[0..1]>/<sha2[2..]>`.
- `key?`, `[]`, `[]=`, `getset(&block)`, `delete`, `clear`.
- Class-level: `Jekyll::Cache.cache_dir=`, `Jekyll::Cache.disable_disk_cache!`,
  `Jekyll::Cache.clear_if_config_changed(config)`.

What we could newly use:

- `clear_if_config_changed` — *Jekyll itself calls this for its own caches*,
  but our two named caches (`CheesyGallery::Render`,
  `CheesyGallery::Geometry`) are not registered with that mechanism. After
  a `_config.yml` change that affects e.g. `max_size` or `quality`, our
  caches keep stale entries. Wiring those caches into the same lifecycle
  (or, more conservatively, including config-fingerprint bytes in the
  cache *key*) would close that gap.
- `disable_disk_cache!` — when `--disable-disk-cache` is passed on the
  CLI, we should not write to either of our named caches.

## 2. What `cheesy-gallery` does today vs. those APIs

| Concern                          | Current implementation                                                                         | API still appropriate? |
|----------------------------------|------------------------------------------------------------------------------------------------|------------------------|
| Discover gallery directories     | `Jekyll::Generator#generate` walking `collection.entries` / `collection.docs`                  | Yes                    |
| Synthesise an index document     | `CheesyGallery::GalleryIndex < Jekyll::Document`, override `read`                              | Yes, with caveats §1.5 |
| Replace each JPG with a renderer | Subclass `Jekyll::StaticFile`, override `write` to skip delete-before-copy and run RMagick     | Yes — no hook exists   |
| Generate per-image thumbnails    | A second `StaticFile` subclass, pushed onto `collection.files`                                 | Yes                    |
| Cache rendered output            | Two named `Jekyll::Cache` instances, keyed by `dest_path` and `realpath#mtime`                 | Yes, but see §1.6      |
| Wire parent/child navigation     | Mutating `doc.data['parent']` / `doc.data['pages']` from inside the generator                  | Yes                    |

The plugin reaches a little deeper than the average plugin (`StaticFile`
subclass with custom `write`, `Document` subclass with overridden
`read_content`), but that depth is justified — there is no shallower API
that does the same job in 4.4.

## 3. Possible architectures going forward

These are presented as alternatives, not a stack ranking. Costs are
relative to "leave it alone".

### 3.1 Stay the course, but tighten

Cheapest path. Keep the generator/StaticFile/Document trio; refresh the
implementation against 4.4 source.

Status as of PR #415 (2026-05-12): three of five bullets landed; one
is moot (Jekyll already covers it); one is still open.

- [x] Override `copy_file(dest_path)` instead of `write(dest)`.
  `copy_file` is the documented integration point that subclasses are
  expected to customise (Active Storage, jekyll-postfiles,
  jekyll_picture_tag all do this), and it lets us drop the bespoke
  "delete-before-copy" workaround in `base_image_file.rb`. _Landed in
  `e118c10`: the RMagick rendering moved into a `copy_file` override
  and the remaining `write` override is just the cross-process Render-
  cache short-circuit._
- [ ] Honour `--disable-disk-cache` for both `CheesyGallery::Render`
  and `CheesyGallery::Geometry`.
- [~] Include a config fingerprint in the cache keys (or call
  `clear_if_config_changed` explicitly) so editing `max_size`
  invalidates geometry entries. _Moot: `cache_spec.rb` "§4:
  invalidation behaviour" verified that Jekyll's `Site#process`
  already calls `Jekyll::Cache.clear_if_config_changed`, which
  `rm -rf`s the whole cache dir and takes both our named caches with
  it._
- [x] Add `safe true` and `priority :low` to the Generator so it
  composes well with other plugins and could be whitelisted under
  `--safe`. _Landed in `8a1602a`._
- [x] Replace the `read_content` override on `GalleryIndex` with a
  `read` override that calls `merge_defaults` + sets `self.content` —
  leaves the private API alone. _Landed in `d5133a6`. Cannot call
  `super`: there is no backing file, so `File.read(path)` would
  `ENOENT` and `handle_read_error` would abort the build under 4.4.1._

Estimated effort: ~half a day, all behind existing tests.

### 3.2 Same architecture, swap RMagick for libvips

The numbers from `jekyll_picture_tag`'s migration and OpsLevel's blog
suggest **5–10× build-time speedup** and **roughly an order of magnitude
less RAM**. RMagick has also had recurring CVE / build-pain issues, while
`ruby-vips` ships as a thin FFI wrapper.

Two ways to land this:

- **Drop-in via the [`image_processing`](https://github.com/janko/image_processing)
  gem.** That gem exposes a single API over both libvips and
  ImageMagick/MiniMagick, so we could keep RMagick as a fallback and
  default to vips. Smallest behavioural risk.
- **Direct `ruby-vips`.** Fewer dependencies, but a chunkier diff in
  `image_file.rb` / `image_thumb.rb`.

Either way, the plugin's external interface (the collection metadata
keys, the generated layout data) does not change. CI matrix needs to
ensure libvips is installed (`apt install libvips`).

Estimated effort: 1–2 days; bulk of the work is parity testing against
existing fixtures.

### 3.3 Split into two gems

Right now `cheesy-gallery` does two distinct things: (a) navigational
"directories of JPGs become a tree of pages with breadcrumbs and a
thumbnail per gallery" and (b) "every JPG gets resized + a square
thumbnail". (a) is the unique value-add; (b) is a commodity.

Possible split:

- `cheesy-gallery` keeps the Generator + GalleryIndex Document + parent/
  child wiring, but stops touching `collection.files` and stops emitting
  `*_thumb.jpg` / `*_index.jpg`.
- Image rendering is delegated to
  [`jekyll-picture-tag`](http://rbuchberger.github.io/jekyll_picture_tag/),
  which already does responsive `<picture>`/`<img srcset>` markup, libvips
  rendering, configurable presets, and respects
  `--disable-disk-cache`. Layouts call `{% picture %}` instead of
  building their own `<img src=...>`.

Pros: smaller surface area for cheesy-gallery, modern responsive markup
for free, drop the `rmagick` runtime dependency entirely. Cons: changes
the layout/template contract for existing sites; users (i.e. cheesy.at)
need a transitional release.

Estimated effort: 2–3 days, mostly layout and migration-guide work.

### 3.4 Build-time script, plugin only does navigation

A more drastic variant of 3.3: drop the plugin's role in image processing
altogether, and make thumbnails / resizes via a `Rakefile` task (or a
small standalone `bin/` script using libvips) that runs *before* `jekyll
build`. The plugin becomes a thin generator that only populates
`doc.data` for the layout.

Pros: thumbnails are no longer rebuilt on every Jekyll site clean,
`--incremental` and `--watch` get cheap, and the plugin no longer needs
RMagick at all.

Cons: split build pipeline; CI needs an extra step; users have to
remember to run `rake thumbs` before `jekyll build`. Probably overkill
for this codebase.

### 3.5 Hooks-based instead of Generator-based (for navigation only)

The work the generator does at `:post_read` time can equivalently be done
via:

```ruby
Jekyll::Hooks.register :site, :post_read do |site|
  CheesyGallery::Wiring.call(site)
end
```

This is mostly a stylistic refactor, but it has one real upside given
the 4.3 `site.static_files` snapshot behaviour: a `:site, :post_read`
hook fires *immediately after* the snapshot is taken, so the manual
"re-sync `site.static_files`" dance currently pushed onto the generator
in `9dd18c0` could be dropped — the hook can mutate the array directly
in place. Worth pairing with §3.3 / §3.4 if we ever adopt them; on its
own it's a small win.

## 4. Recommendation

If `cheesy-gallery` is going to ship one more release on its current
shape, do **§3.1 + §3.2** together: refresh the StaticFile override
against current 4.4 patterns and swap to libvips via `image_processing`.
That's a single coherent perf-and-correctness release that keeps backward
compatibility with existing sites.

The §3.3 split is the right longer-term move, but it's a 2.0-shaped
change and should wait until we've actually written the spec suite that
§4 of `docs/todos.md` calls for — otherwise there is no safety net for
the migration.

## 5. References

- [Jekyll plugins overview](https://jekyllrb.com/docs/plugins/)
- [Jekyll hooks](https://jekyllrb.com/docs/plugins/hooks/) — owner / event
  matrix
- [Jekyll generators](https://jekyllrb.com/docs/plugins/generators/)
- Source: [`lib/jekyll/static_file.rb` @ v4.4.1](https://github.com/jekyll/jekyll/blob/v4.4.1/lib/jekyll/static_file.rb)
- Source: [`lib/jekyll/document.rb` @ v4.4.1](https://github.com/jekyll/jekyll/blob/v4.4.1/lib/jekyll/document.rb)
- Source: [`lib/jekyll/cache.rb` @ v4.4.1](https://github.com/jekyll/jekyll/blob/v4.4.1/lib/jekyll/cache.rb)
- Source: [`lib/jekyll/hooks.rb` @ v4.4.1](https://github.com/jekyll/jekyll/blob/v4.4.1/lib/jekyll/hooks.rb)
- Release notes: [Jekyll 4.4.0](https://jekyllrb.com/news/2025/01/27/jekyll-4-4-0-released/), [4.4.1](https://jekyllrb.com/news/2025/01/29/jekyll-4-4-1-released/), [4.3.0](https://github.com/jekyll/jekyll/releases/tag/v4.3.0), [4.2.0](https://jekyllrb.com/news/2020/12/14/jekyll-4-2-0-released/)
- [`jekyll_picture_tag`](http://rbuchberger.github.io/jekyll_picture_tag/) — reference implementation of a libvips-backed Jekyll image plugin
- [`image_processing`](https://github.com/janko/image_processing) — uniform API over libvips and ImageMagick
- [OpsLevel: Ultra-Fast Thumbnail Generation with Jekyll and libvips](https://www.opslevel.com/resources/ultra-fast-thumbnail-generation-with-jekyll-and-libvips)
