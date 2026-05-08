# Repository Research Report: cheesy-gallery

_Generated: 2026-05-08 — branch `claude/repo-research-report-nap6g`_

## 1. Overview

`cheesy-gallery` is a Ruby gem providing a [Jekyll](https://jekyllrb.com/)
plugin for building photo galleries from directory trees of images. It is
authored by David Schmitt (`david@black.co.at`) and powers the gallery at
<https://www.cheesy.at/fotos/>.

- **Repository:** [DavidS/cheesy-gallery](https://github.com/DavidS/cheesy-gallery)
- **License:** See `LICENSE.md` (MIT-style; project of David Schmitt)
- **Current version:** `1.1.1` (from `lib/cheesy-gallery/version.rb`)
- **Required Ruby:** `>= 2.6.0`
- **Runtime deps:** `jekyll ~> 4.0`, `rmagick >= 4, < 6`
- **Default branch:** `main`
- **Total commits (all refs):** 84
- **First commit:** 2020-08-26
- **Most recent commit on `main`:** 2023-09-27 (`2aee139` — merge of dependabot rmagick 5.3.0 bump)

## 2. What it does

The plugin extends a Jekyll site so that any collection marked with
`cheesy-gallery: true` in `_config.yml` is processed into a navigable photo
gallery:

```yaml
collections:
  my_gallery:
    cheesy-gallery: true
```

For each subdirectory of the collection it:

1. Treats every directory containing files as a gallery; if no `index.md`
   exists, a synthetic `index.html` document is generated.
2. Resizes/optimises every JPG (default `1920x1080`, quality `85`) using
   RMagick, stripping metadata for smaller files.
3. Generates a per-image thumbnail (`*_thumb.jpg`, default 150x150) and a
   per-gallery thumbnail (`*_index.jpg`, default 72x72) using
   `resize_to_fill!` (centre crop).
4. Wires up parent/child navigation between galleries via `data['parent']`
   and `data['pages']`, so the layout can render breadcrumb / sub-gallery
   menus.
5. A file named `thumbnail.jpg` inside a gallery directory is used as that
   gallery's thumbnail source (otherwise the first image is used).

Configurable collection metadata: `max_size`, `quality`,
`gallery_thumbnail_size`, `image_thumbnail_size`, `output`.

## 3. Code layout

```
lib/cheesy-gallery.rb              # entrypoint, loads generator
lib/cheesy-gallery/version.rb      # VERSION = '1.1.1'
lib/cheesy-gallery/generator.rb    # Jekyll::Generator subclass — main logic
lib/cheesy-gallery/gallery_index.rb# Synthetic Document for index-less dirs
lib/cheesy-gallery/base_image_file.rb # StaticFile w/ RMagick + render cache
lib/cheesy-gallery/image_file.rb   # Resized full-size image variant
lib/cheesy-gallery/image_thumb.rb  # Centre-cropped thumbnail variant
spec/cheesy/gallery_spec.rb        # Trivial spec (version + tautology)
spec/fixtures/test_site/           # Real Jekyll site used by CI smoke test
.github/workflows/tests.yaml       # CI: rake spec + jekyll build matrix
.github/workflows/publish.yaml     # All commented out (see §6)
.github/dependabot.yml             # Weekly bundler updates, root + test_site
```

### Notable implementation details

- `BaseImageFile` overrides `Jekyll::StaticFile#write` to (a) skip the
  default delete-before-copy if the destination is already cached and (b)
  route through `process_and_write`, which lets subclasses run RMagick
  transforms instead of a plain copy. A class-level
  `Jekyll::Cache('CheesyGallery::Render')` records what has already been
  rendered.
- `ImageFile` additionally caches geometry (dimensions after `change_geometry!`)
  in a separate `CheesyGallery::Geometry` cache keyed by `realpath#mtime`,
  so dimension reads avoid re-pinging files between builds.
- After processing, the generator sorts `collection.files` by source path,
  intentionally to improve RMagick disk-cache hit rates during rendering.
- `GalleryIndex` is a `Jekyll::Document` subclass that overrides
  `read_content` to inject placeholder content for directories without an
  `index.md`.

## 4. Tests & CI

- **Unit tests** (`spec/cheesy/gallery_spec.rb`) are essentially a smoke
  check — `VERSION` is set and `false == false`. There is no real unit
  coverage of the generator.
- **Integration test** is the GitHub Actions `test-site` job: it runs
  `bundle exec jekyll build --strict --trace --verbose` against
  `spec/fixtures/test_site`, lists `_site/`, dumps a generated HTML page,
  and `file`-checks one rendered thumbnail.
- **CI matrix:** Ruby 2.7, 3.0, 3.1 on `ubuntu-latest`, on `push` and
  `pull_request`. Rubocop runs as part of `rake` (default task).

## 5. Repository state

- Working tree is clean on `claude/repo-research-report-nap6g`.
- Local branches: `main`, `claude/repo-research-report-nap6g` (this branch
  exists on `origin` as well).
- `main` has not received a commit since 2023-09-27. The repo has been in
  maintenance mode (dependabot bumps only) since the v1.1.1 release.

### Recent merges into `main`

```
2aee139 Merge PR #406 (rmagick 4.2.5 → 5.3.0, test_site)
12699a1 Merge PR #407 (TomK32 patch — gallery_index.rb tweak)
c32c6cb Merge PR #402 (tzinfo 2.0.4 → 2.0.6, test_site)
70cbec9 Merge PR #404 (tzinfo-data 1.2022.1 → 1.2023.3, test_site)
76ed50b Merge PR #401 (jekyll 4.2.2 → 4.3.2, test_site)
1845a59 Merge PR #396 (jekyll-feed 0.16.0 → 0.17.0, test_site)
```

## 6. Known issues / loose ends

- **Publish workflow is disabled.** `.github/workflows/publish.yaml` is an
  entirely commented-out file with the header
  `# Doesn't work because of rubygems.org MFA requirements for API access`.
  Releases must currently be cut manually via `bundle exec rake release`.
- **`README.md` Travis reference.** Build/CI section in the README does not
  mention the GHA migration, but commit `9be1aee` ("Replace travis with
  GHA") removed the legacy config. Minor doc drift.
- **Test coverage gap.** Real behaviour is only covered by the fixture
  Jekyll build; there are no specs exercising parent/child wiring,
  caching, geometry computation, or RMagick processing.
- **Open issue #387** (2022): user request for (1) a customisable
  "This page intentionally left blank" default and (2) using the directory
  name as the default page title. Both would land in
  `lib/cheesy-gallery/gallery_index.rb` and the generator. No PR exists.

## 7. Open pull requests

All four open PRs are dependabot bumps targeting the test fixture (none
touch the published gem):

| #   | Title                                                 | Opened     |
|-----|-------------------------------------------------------|------------|
| 410 | Bump jekyll 4.3.2 → 4.3.3 in `/spec/fixtures/test_site` | 2024-01-01 |
| 409 | Bump tzinfo-data 1.2023.3 → 1.2023.4                  | 2023-12-25 |
| 408 | Bump rake 13.0.6 → 13.1.0                             | 2023-10-30 |
| 394 | Update rmagick requirement (root) `~> 4.0` → `>= 4, < 6` | 2022-10-10 |

PR #394 was effectively superseded by the merged PR #406 widening the
constraint, and is stale (auto-rebase disabled after >30 days open). The
others are routine fixture updates safe to merge if CI is green.

## 8. Suggested next steps (if work resumes)

1. **Re-enable publishing.** Either swap to OIDC trusted publishing on
   rubygems.org (now supported and avoids the MFA-API-key issue), or
   document the manual release flow in `README.md`.
2. **Address #387.** Pull title from `File.basename(File.dirname(...))`
   inside `GalleryIndex` and expose `default_content` as a collection
   metadata key.
3. **Refresh CI matrix.** Drop EOL Ruby 2.7/3.0; add 3.2/3.3/3.4 to match
   what dependabot bumps already require (jekyll 4.3.x backports
   target Ruby 3.3).
4. **Add real specs** for the generator — at minimum a fixture-based test
   that asserts navigation linkage and thumbnail attachment.
5. **Close stale PR #394** in favour of the already-merged widening.

## 9. References (in-repo)

- Generator entry: `lib/cheesy-gallery/generator.rb:11`
- Render cache: `lib/cheesy-gallery/base_image_file.rb:8`
- Geometry cache: `lib/cheesy-gallery/image_file.rb:9`
- Thumbnail rendering: `lib/cheesy-gallery/image_thumb.rb:18`
- Synthetic index: `lib/cheesy-gallery/gallery_index.rb:4`
- CI definition: `.github/workflows/tests.yaml:1`
- Disabled publish workflow: `.github/workflows/publish.yaml:1`
