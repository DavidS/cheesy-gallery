# TODOs

Working list for the next round of maintenance on `cheesy-gallery`.
Newer items at the bottom; tick items off in PRs as they land.

## 1. Upgrade Jekyll

- [ ] Bump test fixture (`spec/fixtures/test_site/Gemfile.lock`) from
      Jekyll **4.3.2** to **4.4.1** (current latest, 2025-01-29).
- [ ] Verify `~> 4.0` constraint in `cheesy-gallery.gemspec` still
      makes sense; consider tightening to `~> 4.4` if 4.4 introduces APIs
      we want to rely on, or leave loose if 4.0 compatibility is
      intentional.
- [ ] Close / supersede stale dependabot PRs #410 (4.3.3) and #401-era
      bumps in favour of going straight to 4.4.1.
- [ ] Re-run the fixture build under the new Jekyll and confirm
      `Jekyll::StaticFile`, `Jekyll::Document`, and `Jekyll::Cache`
      surface used by the plugin still match (see §5 below).

## 2. Upgrade Ruby

- [ ] Bump `required_ruby_version` in `cheesy-gallery.gemspec` from
      `>= 2.6.0` to a currently-supported floor (`>= 3.2` recommended).
- [ ] Replace CI matrix in `.github/workflows/tests.yaml` (currently
      `2.7`, `3.0`, `3.1` — all EOL) with the supported lines:
      `3.2`, `3.3`, `3.4`, `4.0`.
- [ ] Update Rubocop's `TargetRubyVersion` in `.rubocop.yml` to match
      the new floor.
- [ ] Re-run `rake` and the fixture `jekyll build` on each version;
      address any new cop offences or deprecation warnings.

## 3. Upgrade other dependencies

- [ ] **rmagick** — gemspec already allows `>= 4, < 6`; bump test_site
      lock to the latest 5.x and confirm `change_geometry!`,
      `resize_to_fill!`, `Magick::Image.ping`, and `interlace=` still
      work as used in `lib/cheesy-gallery/image_file.rb` and
      `image_thumb.rb`.
- [ ] **bundler / rake / rspec / rubocop / pry / codecov** — refresh
      development dependencies to current majors; drop `codecov` if
      coverage uploading is no longer wired up.
- [ ] **test_site fixture deps** — accept or rebase open dependabot
      PRs:
  - [ ] #408 rake 13.0.6 → 13.1.0 (and onward to current)
  - [ ] #409 tzinfo-data 1.2023.3 → 1.2023.4 (and onward)
  - [ ] anything else dependabot has filed since.
- [ ] After dependency churn, regenerate `Gemfile.lock`s and confirm
      both `rake spec` and the fixture `jekyll build` pass.

## 4. Develop a minimal spec suite

Currently `spec/cheesy/gallery_spec.rb` only checks `VERSION` and a
tautology. Build out real coverage of plugin behaviour using the
existing `spec/fixtures/test_site` (or a smaller in-spec fixture):

- [ ] Spec runs `Jekyll::Site#process` end-to-end on a fixture site
      and asserts the generated `_site/` tree contains the expected
      gallery pages, full-size images, `*_thumb.jpg`, and `*_index.jpg`.
- [ ] Test that directories without an `index.md` get a synthetic
      `GalleryIndex` document with `layout: gallery`.
- [ ] Test parent / child wiring (`doc.data['parent']`,
      `doc.data['pages']`) for nested galleries.
- [ ] Test thumbnail selection: explicit `thumbnail.jpg` wins; otherwise
      first image; gallery without images gets no thumbnail.
- [ ] Test image dimension extraction (`data['height'] / ['width']`)
      against fixture JPGs of known size.
- [ ] Test caching: second `process` run with unchanged sources skips
      the RMagick render path (mock or assert via `Jekyll::Cache`).
- [ ] Test `max_size` and `quality` collection-metadata overrides.
- [ ] Wire spec coverage reporting (simplecov) into `rake` if we keep
      coverage as a goal.

## 5. Review Jekyll plugin API surface

The plugin reaches deeper into Jekyll internals than a typical plugin
(subclassing `StaticFile`/`Document`, mutating `collection.files`,
using `Jekyll::Cache` directly). Audit current usage against current
Jekyll docs/source:

- [ ] `Jekyll::Generator` lifecycle: confirm ordering relative to other
      generators and that mutating `collection.files` /
      `collection.docs` from inside `generate` is still supported.
- [ ] `Jekyll::StaticFile`: review the `write` override in
      `lib/cheesy-gallery/base_image_file.rb` against current upstream
      `lib/jekyll/static_file.rb` — the inline comment already calls
      out that we're shadowing internal behaviour, so check for drift
      in 4.3.x → 4.4.x.
- [ ] `Jekyll::Document`: review `GalleryIndex`'s override of
      `read_content` and confirm `cleaned_relative_path`,
      `basename_without_ext`, and `relative_path` semantics match.
- [ ] `Jekyll::Cache`: confirm the two named caches
      (`CheesyGallery::Render`, `CheesyGallery::Geometry`) still
      invalidate correctly on `_config.yml` changes and
      `.jekyll-cache` removal as documented in the README.
- [ ] Frontend hooks: consider whether `Jekyll::Hooks` (e.g.
      `:site, :post_read` or `:documents, :pre_render`) would be a
      cleaner integration point than mutating collections in a
      `Generator`.
- [ ] Document findings in `docs/` (e.g. `docs/jekyll-api-review.md`)
      and update `CLAUDE.md` / `docs/index.md` to link it.
