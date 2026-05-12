# libvips bench

Empirical check on the 5–10× build-time / 10× RAM claims from
`jekyll-api-review.md` §3.2 that motivate the libvips migration.
Methodology and gate live in the migration plan (Plan §0); this file
collects the numbers the bench produces.

Run with `bundle exec ruby script/bench.rb [iterations]`. The script
detects whichever image library the gem currently loads, so the same
invocation is used for both stacks — the diff lives in `Gemfile.lock`
between runs.

## Methodology

- Cold = `rm -rf _site/ .jekyll-cache/` first.
- Warm = re-run the build immediately after cold without removing
  anything; both caches should short-circuit all rendering.
- 5 iterations per (stack, workload) cell. Report min / max / mean /
  median / stddev and call out iter 1 separately.
- Peak RSS sampled from `/proc/self/status:VmHWM` every 50 ms during
  the cold run.

Environment: Ruby 3.3.6, ImageMagick 6.9.12-98 Q16, libvips 8.15.1,
ruby-vips 2.3.0. Container on a shared host — absolute numbers will
move around between machines, ratios should hold.

## Workload A — small fixtures (default)

100 small JPGs (4 sources from `spec/fixtures/test_site/_gallery_two`,
~1000×750, each duplicated 25× into one synthesised gallery). Default
`max_size '1920x1080'` is **larger** than every source, so the
shrink-only `>` flag means the full-size output is a JPEG passthrough
re-encode. Thumbnails go from 1000×750 → 150×150.

Cold wall-clock (s):

| Stack    | min   | max   | mean  | median | stddev | iter 1 | iter 2..5 mean |
|----------|-------|-------|-------|--------|--------|--------|----------------|
| RMagick  | 3.635 | 3.848 | 3.691 | 3.661  | 0.080  | 3.848  | 3.652          |
| libvips  | 4.531 | 5.214 | 4.696 | 4.590  | 0.261  | 5.214  | 4.566          |

Cold peak RSS (KB):

| Stack    | min     | max     | mean    | median  | stddev |
|----------|---------|---------|---------|---------|--------|
| RMagick  | 75 120  | 81 932  | 78 914  | 80 480  | 2 790  |
| libvips  | 121 208 | 129 280 | 125 990 | 127 324 | 2 859  |

Ratio libvips / RMagick on medians: **0.80× speed (libvips slower),
1.58× RAM (libvips worse)**.

## Workload B — DSLR-sized source

20 copies of the 3000×4000 fixture `2012-07-29-Eingeschlafen.jpg`
(`CHEESY_BENCH_DIR=…`). Default `max_size '1920x1080'` means a real
downscale to ~810×1080 (the shrink-on-load path that libvips is
designed around).

Cold wall-clock (s):

| Stack    | min    | max    | mean   | median | stddev | iter 1 | iter 2..5 mean |
|----------|--------|--------|--------|--------|--------|--------|----------------|
| RMagick  | 10.426 | 10.739 | 10.571 | 10.539 | 0.113  | 10.739 | 10.529         |
| libvips  | 3.102  | 3.396  | 3.188  | 3.146  | 0.106  | 3.396  | 3.136          |

Cold peak RSS (KB):

| Stack    | min     | max     | mean    | median  | stddev |
|----------|---------|---------|---------|---------|--------|
| RMagick  | 187 612 | 192 840 | 190 596 | 191 152 | 1 744  |
| libvips  | 165 568 | 174 412 | 170 296 | 170 808 | 3 235  |

Ratio libvips / RMagick on medians: **3.35× speed (libvips wins),
0.89× RAM (libvips slightly better)**.

## Variance and environmental factors

Relative stddev (cold time): RMagick 2.2% / 1.1%, libvips 5.6% / 3.3%.
libvips has higher variance, especially on the small workload, but
both stacks' means are well-separated by workload — the ranking
doesn't flip across iterations.

Sources of variance / per-iteration warmup that affect the absolute
numbers but not the ratios:

- **Disk page cache.** Iter 1 reads JPGs from disk; iter 2+ reads
  from page cache. Effect is ~5% on iter 1 for both stacks
  (symmetric).
- **libvips operation cache.** Library-internal cache of recently-
  compiled operation graphs. First `Vips::Image.thumbnail` call
  compiles, subsequent ones reuse. Iter 1 pays ~0.6 s extra on the
  small workload, ~0.25 s on the large.
- **Ruby JIT.** YJIT is off by default in our setup, so no contribution.
- **libvips threading.** Defaults to `nproc` worker threads.
  `VIPS_CONCURRENCY=1` shaves ~5% off the small workload; not enough
  to change the picture.
- **CPU governor / shared host.** Shared container; cpufreq can drift
  between runs. Largest single contributor to libvips' higher
  small-workload variance.
- **JPEG codec.** Both stacks use libjpeg-turbo under the hood, so
  decode/encode is roughly equivalent per pixel.
- **ICC handling.** libvips' `thumbnail` always runs the ICC import
  → linear-light downsample → export path even for sRGB sources
  without an embedded profile. Adds fixed per-image work — relatively
  more expensive on small images, amortised away on large ones.

None of these factors change the ranking; they just widen the
confidence interval slightly.

## Gate

Plan §0 gate: cold ≥ 3× faster **and** cold peak RSS ≤ 50% of RMagick's.

- Workload A: speed **fails** (0.80×), RAM **fails** (1.58×).
- Workload B: speed **passes** (3.35×), RAM **fails** (0.89×).

Strict reading → **fails on both workloads**. Neither hits the
order-of-magnitude RAM claim that the migration paper cited.

## Interpretation

The published 5–10× / 10× claims (jekyll_picture_tag, OpsLevel)
cover pipelines where libvips' fused decode + shrink-on-load + resize
wins heavily over per-pixel ImageMagick work. cheesy-gallery's
workload is different:

1. **Image sizes vary, often below the resize threshold.** With the
   shrink-only `>` flag from PR #416, sources smaller than `max_size`
   pass through as a JPEG re-encode. libvips has no shrink-on-load
   advantage there — and pays a fixed ICC + threading overhead per
   image.
2. **Only one or two output sizes per source.** The public benchmarks
   typically render `<picture srcset>` permutations (3–6 sizes), which
   amplifies libvips' decode-once / resize-many ergonomics. cheesy
   does full-size + per-image thumb + sometimes a gallery-index thumb.

For sites whose sources are already web-sized (≤ ~1500 px on the long
edge — common for Lightroom export presets), the migration is a small
regression. For sites with DSLR-class sources (≥ 3000 px), the
migration delivers a real 3× speedup on the resize-heavy part of the
build.

Non-perf motivations that the gate doesn't capture:

- Escape from RMagick's recurring CVE / build-pain.
- EXIF Orientation honoured correctly (latent bug under RMagick).

## Status

**Gate failed; proceeded anyway.** The 3.35× speedup on DSLR-class
sources covers the realistic production workload, and the non-perf
wins (escape from RMagick's CVE / build-pain churn, correct EXIF
Orientation handling) carry independent weight. The small-image
regression is acknowledged in `CHANGELOG.md`.

This bench remains in the repo as a regression detector. Re-run it
after any libvips upgrade or image-pipeline change.
