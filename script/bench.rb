#!/usr/bin/env ruby
# frozen_string_literal: true

# Synthetic benchmark for cheesy-gallery's image pipeline.
#
# Runs a cold + warm `Jekyll::Site#process` against a generated fixture
# site and reports wall-clock time and peak RSS. Whichever image
# library the gem currently depends on (RMagick or ruby-vips) is the
# one being measured — the script doesn't toggle libraries, it just
# measures the configured stack.
#
# Usage:
#   bundle exec ruby script/bench.rb [iterations]
#
# Env:
#   CHEESY_BENCH_DIR   path to a directory of JPGs to use instead of
#                      the spec fixtures (recursive). Useful for
#                      larger DSLR-sized inputs.
#   CHEESY_BENCH_COPIES  per-source duplication factor (default 25 for
#                      spec fixtures, 1 for CHEESY_BENCH_DIR).

require 'bundler/setup'
require 'jekyll'
require 'cheesy-gallery'
require 'fileutils'
require 'tmpdir'

ROOT = File.expand_path('..', __dir__)
SPEC_FIXTURE_DIR = File.join(ROOT, 'spec/fixtures/test_site/_gallery_two')
DEFAULT_SOURCES = %w[
  Frostig-001.jpg
  Frostig-003.jpg
  third/Morgenspaziergang-2.jpg
  third/Morgenspaziergang-3.jpg
].map { |rel| File.join(SPEC_FIXTURE_DIR, rel) }.freeze

# Sample VmHWM (high-water-mark RSS, KB) from /proc/self/status every
# 50ms. Linux-only; macOS reviewers can read the wall-clock numbers and
# trust CI for memory.
class RssSampler
  attr_reader :peak_kb

  def initialize(interval: 0.05)
    @interval = interval
    @peak_kb = 0
    @running = false
  end

  def start
    @running = true
    @thread = Thread.new do
      while @running
        sample = read_vm_hwm
        @peak_kb = sample if sample > @peak_kb
        sleep @interval
      end
    end
  end

  def stop
    @running = false
    @thread&.join
    # One final read after the GC settles, since VmHWM is monotonic.
    final = read_vm_hwm
    @peak_kb = final if final > @peak_kb
  end

  private

  def read_vm_hwm
    line = File.read('/proc/self/status').lines.find { |l| l.start_with?('VmHWM:') }
    return 0 unless line

    line.split[1].to_i
  rescue Errno::ENOENT
    0
  end
end

def sources_to_copy
  if (custom = ENV['CHEESY_BENCH_DIR'])
    Dir.glob(File.join(custom, '**', '*.{jpg,JPG,jpeg,JPEG}')).sort
  else
    DEFAULT_SOURCES
  end
end

def copies_factor(sources)
  return Integer(ENV['CHEESY_BENCH_COPIES']) if ENV['CHEESY_BENCH_COPIES']

  (sources == DEFAULT_SOURCES) ? 25 : 1
end

def build_workload!(source_dir, sources, copies)
  FileUtils.mkdir_p(File.join(source_dir, '_layouts'))
  File.write(File.join(source_dir, '_layouts', 'gallery.html'), "---\n---\n{{ content }}\n")

  File.write(File.join(source_dir, '_config.yml'), <<~YAML)
    collections:
      gallery:
        cheesy-gallery: true
    plugins: []
    quiet: true
  YAML

  gallery = File.join(source_dir, '_gallery')
  FileUtils.mkdir_p(gallery)
  File.write(File.join(gallery, 'index.html'), "---\nlayout: gallery\n---\n")

  sources.each_with_index do |src, idx|
    base = File.basename(src, '.*')
    ext  = File.extname(src)
    copies.times do |n|
      FileUtils.cp(src, File.join(gallery, "#{base}-bench-#{idx}-#{n}#{ext}"))
    end
  end

  sources.size * copies
end

def fresh_cold!(source_dir, dest_dir)
  FileUtils.rm_rf(dest_dir)
  FileUtils.rm_rf(File.join(source_dir, '.jekyll-cache'))
end

def measure_build(source_dir, dest_dir)
  sampler = RssSampler.new
  sampler.start
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  config = Jekyll.configuration(
    'source' => source_dir, 'destination' => dest_dir,
    'plugins' => [], 'quiet' => true
  )
  Jekyll::Site.new(config).process

  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
  sampler.stop
  [elapsed, sampler.peak_kb]
end

def detect_library
  if defined?(Vips)
    "ruby-vips #{safe_const(Vips, :VERSION)} / libvips #{safe_call(Vips, :lib_version)}"
  elsif defined?(Magick)
    "rmagick #{safe_const(Magick, :VERSION)} / ImageMagick #{safe_call(Magick, :Magick_version)}"
  else
    'unknown image library'
  end
end

def safe_const(mod, name)
  mod.const_defined?(name) ? mod.const_get(name) : '?'
end

def safe_call(mod, name)
  mod.respond_to?(name) ? mod.public_send(name) : '?'
end

iterations = (ARGV[0] || 5).to_i

source_dir = Dir.mktmpdir('cheesy-bench-src-')
dest_dir   = Dir.mktmpdir('cheesy-bench-dest-')

begin
  sources = sources_to_copy
  copies = copies_factor(sources)
  image_count = build_workload!(source_dir, sources, copies)

  puts 'cheesy-gallery bench'
  puts "  library:     #{detect_library}"
  puts "  ruby:        #{RUBY_DESCRIPTION}"
  puts "  workload:    #{image_count} images (#{sources.size} sources × #{copies} copies)"
  puts "  iterations:  #{iterations}"
  puts

  cold_times = []
  cold_rss   = []
  warm_times = []

  iterations.times do |i|
    fresh_cold!(source_dir, dest_dir)
    elapsed, peak_kb = measure_build(source_dir, dest_dir)
    cold_times << elapsed
    cold_rss << peak_kb
    printf "  cold #{i + 1}: %7.3fs  peak RSS %d KB\n", elapsed, peak_kb

    # Warm: same source_dir/.jekyll-cache, do not rm anything.
    elapsed_warm, = measure_build(source_dir, dest_dir)
    warm_times << elapsed_warm
    printf "  warm #{i + 1}: %7.3fs\n", elapsed_warm
  end

  stats = ->(xs) do
    sorted = xs.sort
    n = sorted.size
    mean = sorted.sum.to_f / n
    median = n.odd? ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
    variance = sorted.sum { |x| (x - mean)**2 } / n
    { min: sorted.first, max: sorted.last, mean: mean, median: median, stddev: Math.sqrt(variance) }
  end

  ct = stats.call(cold_times)
  cr = stats.call(cold_rss)
  wt = stats.call(warm_times)

  # Iteration 1 carries one-off costs (cold disk cache, Ruby JIT warmup,
  # libvips operation-cache prime). Report it alongside the steady-state
  # so reviewers can spot warmup-dominated workloads.
  i1_cold  = cold_times.first
  i1_rss   = cold_rss.first
  rest     = stats.call(cold_times.drop(1))
  rest_rss = stats.call(cold_rss.drop(1))

  puts
  puts '  cold wall-clock (s):'
  printf "    min %7.3f  max %7.3f  mean %7.3f  median %7.3f  stddev %.3f\n",
         ct[:min], ct[:max], ct[:mean], ct[:median], ct[:stddev]
  printf "    iter 1 %7.3f  iter 2..N  min %7.3f  max %7.3f  mean %7.3f\n",
         i1_cold, rest[:min], rest[:max], rest[:mean]
  puts '  cold peak RSS (KB):'
  printf "    min %d  max %d  mean %.0f  median %.0f  stddev %.0f\n",
         cr[:min], cr[:max], cr[:mean], cr[:median], cr[:stddev]
  printf "    iter 1 %d  iter 2..N  min %d  max %d  mean %.0f\n",
         i1_rss, rest_rss[:min], rest_rss[:max], rest_rss[:mean]
  puts '  warm wall-clock (s):'
  printf "    min %7.3f  max %7.3f  mean %7.3f  median %7.3f  stddev %.3f\n",
         wt[:min], wt[:max], wt[:mean], wt[:median], wt[:stddev]
  printf "  per-image (cold median): %5.1f ms\n", ct[:median] * 1000.0 / image_count
ensure
  FileUtils.remove_entry(source_dir, true) if File.exist?(source_dir)
  FileUtils.remove_entry(dest_dir, true)   if File.exist?(dest_dir)
end
