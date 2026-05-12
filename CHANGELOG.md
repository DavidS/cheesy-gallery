# 1.2.0

## User-visible changes

### Breaking

* **Install:** image processing switched from RMagick to libvips (via
  [ruby-vips](https://github.com/libvips/ruby-vips)). Install `libvips`
  (e.g. `apt install libvips42 libvips-dev` or `brew install vips`)
  instead of ImageMagick / libmagickwand-dev. See
  `docs/libvips-bench.md` for the perf comparison that motivated the
  swap.
* **Ruby:** `required_ruby_version` raised from `>= 2.6.0` to `>= 3.2`.
  CI now runs on 3.2 / 3.3 / 3.4 / 4.0.
* **Jekyll:** gem constraint tightened from `~> 4.0` to `~> 4.4`. The
  plugin now relies on Jekyll 4.3+ collection-read semantics and on
  the 4.4 `Document#read` shape.

### Behaviour

* **Shrink-only rendering:** the default geometry (`1920x1080`) and
  any user-supplied `max_size` without an explicit geometry flag now
  append `>`, so sources smaller than the bounding box are passed
  through at their original dimensions instead of being upscaled. The
  geometry is part of both the Geometry- and Render-cache keys, so
  upgrading invalidates stale upscaled outputs automatically — no
  `jekyll clean` required.
* **EXIF Orientation** is now honoured. Sources that previously
  rendered sideways (Orientation 5–8) will now render upright. Output
  JPEGs no longer carry the orientation tag.
* **Encoder defaults:** every rendered JPEG (full-size + thumbs) now
  ships as a progressive JPEG with optimised Huffman tables, explicit
  4:2:0 chroma subsampling, and all metadata stripped (`keep: :none`).
  Thumbnails are encoded at Q80; full-size renders honour the
  collection-metadata `quality` value (default 85). Previously
  thumbnails used RMagick's default encoder (baseline JPEG, ~Q75, EXIF
  retained). The explicit `subsample_mode: :on` guards against a
  silent ~25% file-size jump if `quality` is bumped to ≥ 90 (where
  libvips' `:auto` mode would otherwise switch to 4:4:4).
* **`max_size` narrowing:** values with ImageMagick trailing flags
  other than `>` (i.e. `!`, `^`, `@`, `#`) are silently treated as
  the plain `WxH` form. cheesy-gallery's own config never used these
  flags; if you depended on them, file an issue.
* **Generator metadata:** the generator now declares `safe true` (so
  it whitelists under `jekyll build --safe`) and `priority :low` (so
  it runs after default-priority generators).

### Bug fixes

* **Render-cache staleness:** the Render-cache key now includes
  source `mtime`, so in-place edits or re-pointed `git-annex`
  symlinks no longer silently keep stale renders on subsequent
  builds.
* **Jekyll 4.3+ compat:** `Collection#read` snapshots
  `collection.files` into `site.static_files`, so the generator now
  re-syncs `site.static_files` after mutating `collection.files`.
  Without this, generator-added files (thumbs / index renders)
  silently never reached the writer.
* **Jekyll 4.4.1 compat:** the synthetic `GalleryIndex` document now
  overrides `Document#read` directly (rather than the private
  `read_content`), avoiding an `ENOENT` crash from `read_post_data`
  on the non-existent backing file.
* **Robustness:** image header reads now use `fail_on: :error`, so a
  truncated or corrupt source JPEG aborts the build with a clear
  error rather than silently rendering a half-grey output.

## Internal changes

* CI matrix expanded to Ruby 3.2 / 3.3 / 3.4 / 4.0; `actions/checkout`
  bumped to v4; superseded workflow runs auto-cancel per branch;
  tests run on push only.
* `BaseImageFile` render path refactored: rendering now happens inside
  a `copy_file` override; the `write` override is now just the
  cross-process Render-cache short-circuit. The bespoke `mkdir_p` +
  `rm` dance was dropped in favour of `super`.
* Dev dependencies: `codecov` dropped (CI never uploaded coverage);
  `bundler` dev dep loosened to `>= 2.1`. Fixture lockfile refreshed
  (rake 13.4.2, tzinfo-data 1.2026.2, plus jekyll, jekyll-feed,
  jekyll-seo-tag, minima, kramdown, rouge, listen, sass-embedded, et
  al. to current within constraints).
* New spec suites: `spec/cheesy/generator_spec.rb` (end-to-end gallery
  generation, parent/child wiring, thumbnail selection, dimension
  extraction, `max_size` / `quality` overrides) and
  `spec/cheesy/cache_spec.rb` (eight cache-layer scenarios derived
  from `docs/cache-analysis.md`).
* New internal docs under `docs/`: `repo-research-report.md`,
  `jekyll-api-review.md`, `cache-analysis.md`, `libvips-bench.md`,
  `index.md`, `todos.md`. Bench script at `script/bench.rb`.

# 1.1.1

* Address some deprecations warnings thanks to @pdxmph
* CI housekeeping: move to GHA from travis

# 1.1.0

* Adds aggressive caching to reduce rebuild times.
  If you need to re-render images for any reason, remove the `.jekyll-cache` folder or change the `_config.yml` file.

* Changes default quality to 85, and instead strips alls comments.
  This results in better quality pictures with less size.

# 1.0.0

Initial Release
