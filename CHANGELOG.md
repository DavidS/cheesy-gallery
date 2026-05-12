# 1.2.0

* **Breaking install change:** image processing switched from RMagick
  to libvips (via [ruby-vips](https://github.com/libvips/ruby-vips)).
  Install `libvips` (e.g. `apt install libvips42 libvips-dev` or
  `brew install vips`) instead of ImageMagick / libmagickwand-dev. See
  `docs/libvips-bench.md` for the perf comparison that motivated the
  swap.
* **Behaviour change:** EXIF Orientation is now honoured. Sources that
  previously rendered sideways (Orientation 5–8) will now render
  upright. Output JPEGs no longer carry the orientation tag.
* **Behaviour change:** thumbnails (`*_thumb.jpg`, `*_index.jpg`) are
  now progressive JPEGs encoded at Q80 with optimised Huffman tables
  and EXIF metadata stripped. Previously they used RMagick's default
  encoder settings (baseline JPEG, ~Q75, EXIF retained).
* **Behaviour narrowing:** `max_size` values with ImageMagick trailing
  flags other than `>` (i.e. `!`, `^`, `@`, `#`) are silently treated
  as the plain `WxH` form. cheesy-gallery's own config never used
  these flags; if you depended on them, file an issue.

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
