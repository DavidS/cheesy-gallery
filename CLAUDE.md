# CLAUDE.md

## Project

`cheesy-gallery` — a Ruby gem providing a Jekyll plugin that turns
directory trees of JPGs into navigable, RMagick-rendered photo galleries.
Powers <https://www.cheesy.at/fotos/>.

## Structure

- `lib/cheesy-gallery/` — plugin source (generator, image/thumbnail
  static-file subclasses, synthetic gallery index document, version).
- `spec/cheesy/` — RSpec specs (smoke only).
- `spec/fixtures/test_site/` — real Jekyll site used as the integration
  test in CI.
- `.github/workflows/` — GHA: `tests.yaml` runs `rake` and a fixture
  `jekyll build`; `publish.yaml` is currently disabled.
- `docs/` — internal documentation and reports. Start at
  [`docs/index.md`](docs/index.md).

## Dev

- Setup: `bin/setup`
- Tests: `rake spec` (default `rake` also runs Rubocop)
- Console: `bin/console`
- Required Ruby: `>= 2.6.0`

## Further reading

See [`docs/index.md`](docs/index.md) for reports and deeper notes.
