# TODOs

Working list for the next round of maintenance on `cheesy-gallery`.
Newer items at the bottom; tick items off in PRs as they land.

## 0. Behavioural follow-ups

- [x] Consider adding the `>` modifier to the `change_geometry!`
      geometry strings in `lib/cheesy-gallery/image_file.rb`. Today
      the plugin uses bare `'1920x1080'` (and whatever `max_size`
      collection metadata supplies) which, per ImageMagick geometry
      semantics, *enlarges* originals smaller than the box. For a
      photo gallery the more useful behaviour is "shrink to fit, but
      never upscale" — i.e. `'1920x1080>'`. _Done: `ImageFile` now
      normalises `max_size` via a private `geometry_string` that
      appends `>` unless the user already supplied a geometry flag
      (`!`, `<`, `>`, `^`, `@`, `#`). The geometry is also mixed
      into the Geometry-cache key (via the `realpath#mtime#geom`
      shape) and the Render-cache key (via a new
      `render_cache_discriminator` hook on `BaseImageFile`), so
      upgrading the plugin invalidates stale upscaled outputs
      automatically — no `jekyll clean` required. `generator_spec.rb`
      now pins the new behaviour (1000×750 source → 1000×750 output
      under default `'1920x1080'`); `cache_spec.rb` covers both new
      key shapes._

## 1. Upgrade Jekyll

- [x] Bump test fixture (`spec/fixtures/test_site/Gemfile.lock`) from
      Jekyll **4.3.2** to **4.4.1** (current latest, 2025-01-29).
- [x] Verify `~> 4.0` constraint in `cheesy-gallery.gemspec` still
      makes sense; consider tightening to `~> 4.4` if 4.4 introduces APIs
      we want to rely on, or leave loose if 4.0 compatibility is
      intentional. _Tightened to `~> 4.4`. Jekyll 4.3.0 changed
      `Collection#read` to snapshot `collection.files` into
      `site.static_files` (requires the `9dd18c0` re-sync in the
      generator), 4.4.x is what the StaticFile/Document overrides
      have actually been validated against (PR #415), and the
      Render-cache mtime fix (`e118c10`) keys on Jekyll's current
      cache surface — no reason to keep claiming 4.0 / 4.1 / 4.2
      compatibility._
- [x] Close / supersede stale dependabot PRs #410 (4.3.3) and #401-era
      bumps in favour of going straight to 4.4.1. _Verified via the
      GitHub API: all four stale PRs were closed (unmerged) on
      2026-05-12 alongside PR #412 — #410 (jekyll 4.3.2 → 4.3.3),
      #408 (rake 13.0.6 → 13.1.0), #409 (tzinfo-data 1.2023.3 →
      1.2023.4), and #394 (rmagick widening, already superseded by
      the merged PR #406). Nothing else is open against the repo._
- [x] Re-run the fixture build under the new Jekyll and confirm
      `Jekyll::StaticFile`, `Jekyll::Document`, and `Jekyll::Cache`
      surface used by the plugin still match (see §5 below). _Surfaced
      a latent bug: since Jekyll 4.3, `Collection#read` snapshots
      `collection.files` into `site.static_files`, so the generator's
      in-place mutations no longer reach the writer. Fixed in
      `lib/cheesy-gallery/generator.rb` by re-syncing `site.static_files`
      at the end of each per-collection block._

## 2. Upgrade Ruby

- [x] Bump `required_ruby_version` in `cheesy-gallery.gemspec` from
      `>= 2.6.0` to a currently-supported floor (`>= 3.2` recommended).
- [x] Replace CI matrix in `.github/workflows/tests.yaml` (currently
      `2.7`, `3.0`, `3.1` — all EOL) with the supported lines:
      `3.2`, `3.3`, `3.4`, `4.0`. _Also bumped `actions/checkout` to v4._
- [x] Update Rubocop's `TargetRubyVersion` in `.rubocop.yml` to match
      the new floor.
- [ ] Re-run `rake` and the fixture `jekyll build` on each version;
      address any new cop offences or deprecation warnings. _Local run
      under Ruby 3.3 is clean; awaiting CI matrix run for the rest._

## 3. Upgrade other dependencies

- [x] **rmagick** — gemspec already allows `>= 4, < 6`; bump test_site
      lock to the latest 5.x and confirm `change_geometry!`,
      `resize_to_fill!`, `Magick::Image.ping`, and `interlace=` still
      work as used in `lib/cheesy-gallery/image_file.rb` and
      `image_thumb.rb`. _Bumped to rmagick 5.5.0; fixture build
      produces the expected `*_thumb.jpg` / `*_index.jpg`._
- [x] **bundler / rake / rspec / rubocop / pry / codecov** — refresh
      development dependencies to current majors; drop `codecov` if
      coverage uploading is no longer wired up. _CI never uploaded
      coverage; dropped `codecov` from the gemspec and `spec_helper.rb`.
      Loosened the `bundler` dev dep to `>= 2.1`. The other constraints
      (`rake ~> 13.0`, `rspec ~> 3.0`) already cover current majors._
- [x] **test_site fixture deps** — accept or rebase open dependabot
      PRs:
  - [x] #408 rake 13.0.6 → 13.1.0 (and onward to current). _Bumped to
        13.4.2._
  - [x] #409 tzinfo-data 1.2023.3 → 1.2023.4 (and onward). _Bumped to
        1.2026.2._
  - [x] anything else dependabot has filed since. _`bundle update`
        also moved jekyll, jekyll-feed, jekyll-seo-tag, minima, kramdown,
        rouge, listen, sass-embedded, et al. to current within
        constraints._
- [x] After dependency churn, regenerate `Gemfile.lock`s and confirm
      both `rake spec` and the fixture `jekyll build` pass.

## 4. Develop a minimal spec suite

Currently `spec/cheesy/gallery_spec.rb` only checks `VERSION` and a
tautology. Build out real coverage of plugin behaviour using the
existing `spec/fixtures/test_site` (or a smaller in-spec fixture):

- [x] Spec runs `Jekyll::Site#process` end-to-end on a fixture site
      and asserts the generated `_site/` tree contains the expected
      gallery pages, full-size images, `*_thumb.jpg`, and `*_index.jpg`.
      _Landed in `spec/cheesy/generator_spec.rb`: builds an ephemeral
      tmpdir mirroring the canonical two-collection layout
      (`gallery_one` with explicit `index.html`, `gallery_two` with a
      synthetic root + nested `third/` subgallery) and asserts 6
      full-size renders, 6 `*_thumb.jpg`, 3 `*_index.jpg`, and an
      `index.html` for every gallery._
- [x] Test that directories without an `index.md` get a synthetic
      `GalleryIndex` document with `layout: gallery`. _`generator_spec.rb`
      asserts the doc for `_gallery_two/` is a `CheesyGallery::GalleryIndex`,
      has `data['layout'] == 'gallery'`, and its content equals
      `DEFAULT_CONTENT`; explicit index.html docs are plain
      `Jekyll::Document` (sanity check)._
- [x] Test parent / child wiring (`doc.data['parent']`,
      `doc.data['pages']`) for nested galleries. _Covered in
      `generator_spec.rb`: roots have `parent == nil`,
      `gallery_two/third` has the synthetic gallery_two doc as parent,
      `gallery_two`'s `data['pages']` includes the `third` doc, leaves
      have an empty `pages` list._
- [x] Test thumbnail selection: explicit `thumbnail.jpg` wins; otherwise
      first image; gallery without images gets no thumbnail. _Three
      examples in `generator_spec.rb` cover all branches; the
      explicit-`thumbnail.jpg` case also asserts the chosen image is
      filtered out of `doc.data['images']` (matches generator behaviour
      at `generator.rb:73`)._
- [x] Test image dimension extraction (`data['height'] / ['width']`)
      against fixture JPGs of known size. _`generator_spec.rb` pins
      `change_geometry!('1920x1080')` behaviour (1000x750 → 1440x1080,
      since the geometry has no `>` modifier) and the `600x400`
      override (1000x750 → 533x400). Note: a follow-up could revisit
      whether the upscale-by-default semantics are actually desired
      — that's a behavioural decision, not a bug._
- [x] Test caching: second `process` run with unchanged sources skips
      the RMagick render path (mock or assert via `Jekyll::Cache`).
      _Landed in `spec/cheesy/cache_spec.rb` (PR #414, 2026-05-12):
      eight scenarios from `docs/cache-analysis.md` §3.3 + §1/§4/§5
      details, with `Magick::Image.ping` and `Magick::ImageList.new`
      spies asserting per-layer hits/misses. Surfaced two doc
      corrections (`_config.yml` DOES invalidate both named caches;
      `ImageThumb.mtimes` is shared between `*_thumb.jpg` and
      `*_index.jpg`) and a real Render-cache staleness bug — see §5
      below._
- [x] Test `max_size` and `quality` collection-metadata overrides.
      _`generator_spec.rb` asserts both: the rendered `gallery_two`
      output (max_size `600x400`) fits within the bounding box, the
      default `gallery_one` output renders at 1440x1080, and the
      `ImageFile` instances carry the expected `@max_size` / `@quality`
      values straight from `collection.metadata` (gallery_one quality
      70 from explicit config; gallery_two defaults to 85)._
- [ ] Wire spec coverage reporting (simplecov) into `rake` if we keep
      coverage as a goal.

## 5. Review Jekyll plugin API surface

The plugin reaches deeper into Jekyll internals than a typical plugin
(subclassing `StaticFile`/`Document`, mutating `collection.files`,
using `Jekyll::Cache` directly). Audit current usage against current
Jekyll docs/source:

- [x] `Jekyll::Generator` lifecycle: confirm ordering relative to other
      generators and that mutating `collection.files` /
      `collection.docs` from inside `generate` is still supported.
      _Mutating `collection.files` is no longer enough since Jekyll
      4.3.0: `Collection#read` snapshots the files into
      `site.static_files`, and `Site#each_site_file` writes from that
      array. The generator now re-syncs `site.static_files` after
      mutating `collection.files`. Re-evaluate whether moving to a
      `:site, :post_read` hook (see below) would be cleaner._
- [x] `Jekyll::StaticFile`: review the `write` override in
      `lib/cheesy-gallery/base_image_file.rb` against current upstream
      `lib/jekyll/static_file.rb` — the inline comment already calls
      out that we're shadowing internal behaviour, so check for drift
      in 4.3.x → 4.4.x. _Reviewed and tightened in PR #415
      (`e118c10`): RMagick rendering moved into a `copy_file`
      override, the bespoke `mkdir_p` + `rm` dance dropped in favour
      of deferring to `super`, and the remaining `write` override is
      now just the cross-process Render-cache short-circuit. Same
      commit fixes a Layer-B-shadows-Layer-A staleness bug by adding
      source `mtime` to the Render-cache key — without it, in-place
      source edits (or re-pointed git-annex symlinks) were silently
      skipped on subsequent builds._
- [x] `Jekyll::Document`: review `GalleryIndex`'s override of
      `read_content` and confirm `cleaned_relative_path`,
      `basename_without_ext`, and `relative_path` semantics match.
      _Done in PR #415 (`d5133a6`): `read_content` is private in
      Jekyll 4.x and the synthetic doc has no backing file, so
      calling `super` from a `read` override hit `ENOENT` and
      `handle_read_error` aborted the build under 4.4.1.
      `GalleryIndex` now overrides `read` directly (without calling
      `super`) and invokes the still-private `merge_defaults`
      itself, mirroring Jekyll's sequence minus the file I/O; skipping
      `read_post_data` is intentional (it would touch
      `File.mtime(path)` on the synthetic path)._
- [x] `Jekyll::Cache`: confirm the two named caches
      (`CheesyGallery::Render`, `CheesyGallery::Geometry`) still
      invalidate correctly on `_config.yml` changes and
      `.jekyll-cache` removal as documented in the README.
      _Verified end-to-end by `spec/cheesy/cache_spec.rb` (PR #414).
      Note: `_config.yml` edits **do** invalidate both named caches
      — `Jekyll::Cache.clear_if_config_changed` from `Site#process`
      `rm -rf`s the whole `cache_dir`, contrary to an earlier note
      in `docs/cache-analysis.md` (since corrected). The Render
      cache is **not** self-healing under Marshal corruption (Geometry
      cache is, via `getset`'s `StandardError` rescue)._
- [x] Frontend hooks: consider whether `Jekyll::Hooks` (e.g.
      `:site, :post_read` or `:documents, :pre_render`) would be a
      cleaner integration point than mutating collections in a
      `Generator`. _Evaluated in `docs/jekyll-api-review.md` §3.5
      and decided in PR #415 (branch `stay-course-tighten`) to keep
      the `Generator` for this release. A `:site, :post_read` hook
      would let us drop the `9dd18c0` `site.static_files` re-sync,
      but it's only a small win on its own and is better paired with
      the §3.3 libvips split when (if) we tackle it. Same PR added
      `safe true` and `priority :low` to the generator
      (`8a1602a`) so it whitelists under `--safe` and runs after
      default-priority generators — synthetic `GalleryIndex` docs
      remain invisible to earlier generators, which is acceptable for
      current deployments._
- [x] Document findings in `docs/jekyll-api-review.md` and link it from
      `docs/index.md` (2026-05-10).
