# frozen_string_literal: true

require 'spec_helper'
require 'jekyll'
require 'fileutils'
require 'tmpdir'
require 'rmagick'

# Cache behaviour specs for cheesy-gallery.
#
# Each scenario below maps to one of the eight cases enumerated in
# docs/cache-analysis.md §3.3. Implementation notes (matching §4-§6
# of that document) get their own describe blocks at the end.
#
# How the cache is checked
# ------------------------
# The expensive operations that the caches are designed to short-circuit
# are:
#
#   * `Magick::Image.ping(path)` — runs inside `CheesyGallery::ImageFile`'s
#     Geometry-cache `getset` block. Exactly one call per source image
#     on a Geometry-cache miss; zero calls on a hit.
#
#   * `Magick::ImageList.new(path)` — the first line of
#     `BaseImageFile#copy_file`, which is reached only when Layer A
#     (mtimes/dest existence) and Layer B (Render cache) both miss.
#     Exactly one call per variant on a Layer-B miss; zero calls on
#     a hit.
#
# We install spies via `and_wrap_original` so the original calls still
# happen (we want real Jekyll output) and assert per-scenario counts.
# Corroborating signals: destination file mtimes (preserved on a hit,
# reset to source mtime on a miss) and `.jekyll-cache/` blobs on disk.
#
# We simulate a cold `jekyll build` process between successive `build!`
# calls by clearing in-memory class state without touching the on-disk
# cache or the rendered `_site/` tree — that's the only state a fresh
# Ruby process would actually have lost.
# Use the smaller _gallery_two JPGs (~1000x750) to keep RMagick work
# cheap across the matrix of scenarios.
CHEESY_CACHE_FIXTURE_DIR  = File.expand_path('../fixtures/test_site/_gallery_two', __dir__)
CHEESY_CACHE_FIXTURE_JPGS = %w[Frostig-001.jpg Frostig-003.jpg].freeze

RSpec.describe 'cheesy-gallery cache behaviour' do
  attr_accessor :ping_count, :decode_count, :ping_paths, :decode_paths

  let(:source_dir) { Dir.mktmpdir('cheesy-cache-spec-source-') }
  let(:dest_dir)   { Dir.mktmpdir('cheesy-cache-spec-dest-')   }

  let(:render_cache)   { CheesyGallery::BaseImageFile.class_variable_get(:@@render_cache) }
  let(:geometry_cache) { CheesyGallery::ImageFile.class_variable_get(:@@geometry_cache) }

  before do
    install_spies!
    write_fixture_site
    simulate_cold_process!
  end

  after do
    FileUtils.remove_entry(source_dir, true) if File.exist?(source_dir)
    FileUtils.remove_entry(dest_dir,   true) if File.exist?(dest_dir)
    simulate_cold_process!
  end

  # --- helpers ---------------------------------------------------------

  def install_spies!
    @ping_count   = 0
    @decode_count = 0
    @ping_paths   = []
    @decode_paths = []
    allow(Magick::Image).to receive(:ping).and_wrap_original do |orig, *args|
      @ping_count += 1
      @ping_paths << args.first
      orig.call(*args)
    end
    allow(Magick::ImageList).to receive(:new).and_wrap_original do |orig, *args|
      @decode_count += 1
      @decode_paths << args.first
      orig.call(*args)
    end
  end

  def reset_counters!
    @ping_count   = 0
    @decode_count = 0
    @ping_paths   = []
    @decode_paths = []
  end

  # Simulate a fresh `jekyll build` process: drop the in-memory parts of
  # every relevant cache, but leave .jekyll-cache/ and _site/ alone.
  #
  # Also resets `@base_dir` on the cache instances — they memoise the
  # on-disk path on first use, and would otherwise stay pinned to a
  # *previous* example's source_dir, sending all I/O to the wrong tree.
  def simulate_cold_process!
    Jekyll::StaticFile.reset_cache
    [CheesyGallery::BaseImageFile, CheesyGallery::ImageFile, CheesyGallery::ImageThumb].each do |k|
      k.reset_cache if k.respond_to?(:reset_cache)
    end
    if CheesyGallery::BaseImageFile.class_variable_defined?(:@@render_cache)
      render_cache.instance_variable_get(:@cache).clear
      render_cache.instance_variable_set(:@base_dir, nil)
    end
    return unless CheesyGallery::ImageFile.class_variable_defined?(:@@geometry_cache)

    geometry_cache.instance_variable_get(:@cache).clear
    geometry_cache.instance_variable_set(:@base_dir, nil)
  end

  def write_fixture_site
    FileUtils.mkdir_p(File.join(source_dir, '_gallery'))
    CHEESY_CACHE_FIXTURE_JPGS.each do |jpg|
      FileUtils.cp(File.join(CHEESY_CACHE_FIXTURE_DIR, jpg), File.join(source_dir, '_gallery'))
    end
    File.write(File.join(source_dir, '_config.yml'), <<~YAML)
      collections:
        gallery:
          cheesy-gallery: true
          output: true
      plugins: []
      quiet: true
    YAML
    FileUtils.mkdir_p(File.join(source_dir, '_layouts'))
    File.write(File.join(source_dir, '_layouts', 'gallery.html'), "---\n---\n{{ content }}\n")
  end

  def build!
    config = Jekyll.configuration(
      'source' => source_dir,
      'destination' => dest_dir,
      'plugins' => [],
      'quiet' => true,
    )
    Jekyll::Site.new(config).process
  end

  def dest_jpgs
    Dir.glob(File.join(dest_dir, 'gallery', '*.jpg'))
  end

  # Jekyll 4.x stores caches under `<source>/.jekyll-cache/Jekyll/Cache/`
  # (see Jekyll::Site#configure_cache, which sets
  # `Jekyll::Cache.cache_dir = in_source_dir(config['cache_dir'], 'Jekyll/Cache')`).
  def render_cache_files
    Dir.glob(File.join(source_dir, '.jekyll-cache', 'Jekyll', 'Cache',
                       'CheesyGallery--Render', '**', '*'))
       .select { |p| File.file?(p) }
  end

  def geometry_cache_files
    Dir.glob(File.join(source_dir, '.jekyll-cache', 'Jekyll', 'Cache',
                       'CheesyGallery--Geometry', '**', '*'))
       .select { |p| File.file?(p) }
  end

  # --- §3.3 scenario 1: cold first build -----------------------------

  describe 'scenario 1: cold first build' do
    it 'pings every source exactly once (Geometry cache misses for all)' do
      build!
      expect(@ping_count).to eq(CHEESY_CACHE_FIXTURE_JPGS.size)
    end

    it 'decodes every variant (Render cache misses for all)' do
      build!
      # 2 sources × (full + per-image thumb) + 1 gallery index thumb = 5 decodes
      expect(@decode_count).to eq(CHEESY_CACHE_FIXTURE_JPGS.size * 2 + 1)
    end

    it 'persists Render and Geometry cache blobs under .jekyll-cache/' do
      build!
      expect(geometry_cache_files.size).to eq(CHEESY_CACHE_FIXTURE_JPGS.size)
      expect(render_cache_files.size).to eq(CHEESY_CACHE_FIXTURE_JPGS.size * 2 + 1)
    end

    it 'sets dest mtimes equal to source mtimes (utime trick)' do
      build!
      source = File.join(source_dir, '_gallery', CHEESY_CACHE_FIXTURE_JPGS.first)
      out    = File.join(dest_dir,   'gallery',  CHEESY_CACHE_FIXTURE_JPGS.first)
      expect(File.mtime(out).to_i).to eq(File.mtime(source).to_i)
    end
  end

  # --- §3.3 scenario 2: warm second build, no source changes ---------

  describe 'scenario 2: warm second build, no source changes' do
    it 'does no RMagick work at all (Layers B and C both hit)' do
      build!
      simulate_cold_process!
      reset_counters!
      build!
      expect(@ping_count).to   eq(0), 'Geometry cache (Layer C) should hit on every source'
      expect(@decode_count).to eq(0), 'Render cache (Layer B) should hit on every variant'
    end

    it 'leaves rendered dest files untouched (no rewrite)' do
      build!
      mtimes_before = dest_jpgs.to_h { |f| [f, File.mtime(f)] }
      simulate_cold_process!
      build!
      dest_jpgs.each do |f|
        expect(File.mtime(f)).to eq(mtimes_before[f]),
                                 "#{File.basename(f)} was rewritten on a no-op build"
      end
    end
  end

  # --- §3.3 scenario 3: warm build with one new photo ----------------

  describe 'scenario 3: warm build with one new photo' do
    it 'only does RMagick work for the new source' do
      build!
      simulate_cold_process!
      new_jpg = File.join(source_dir, '_gallery', 'zzz-new-photo.jpg')
      FileUtils.cp(File.join(CHEESY_CACHE_FIXTURE_DIR, CHEESY_CACHE_FIXTURE_JPGS.first), new_jpg)
      reset_counters!
      build!

      expect(@ping_count).to eq(1), 'only the new source should be pinged'
      # The new photo gets a full + a thumb decode. It's not the
      # alphabetically-first image (zzz-…), so the gallery index thumb
      # stays cached.
      expect(@decode_count).to eq(2)
      expect(@decode_paths.uniq).to eq([new_jpg])
    end
  end

  # --- §3.3 scenario 4: edited source, dest_path unchanged ------------

  describe 'scenario 4: source edited in place, dest_path unchanged' do
    it 're-renders because the Render-cache key includes the source mtime' do
      build!
      target_source = File.join(source_dir, '_gallery', CHEESY_CACHE_FIXTURE_JPGS.first)
      target_dest   = File.join(dest_dir,   'gallery',  CHEESY_CACHE_FIXTURE_JPGS.first)
      original_dest_mtime = File.mtime(target_dest)

      # Simulate an in-place edit by bumping the source mtime.
      future = Time.now + 60
      File.utime(future, future, target_source)

      simulate_cold_process!
      reset_counters!
      build!

      expect(@decode_count).to be > 0
      expect(File.mtime(target_dest)).not_to eq(original_dest_mtime)
    end
  end

  # --- §3.3 scenario 5: after `jekyll clean` -------------------------

  describe 'scenario 5: after `jekyll clean`' do
    it 'is indistinguishable from scenario 1' do
      build!
      FileUtils.rm_rf(File.join(source_dir, '.jekyll-cache'))
      FileUtils.rm_rf(dest_dir)
      FileUtils.mkdir_p(dest_dir)
      simulate_cold_process!
      reset_counters!
      build!

      expect(@ping_count).to   eq(CHEESY_CACHE_FIXTURE_JPGS.size)
      expect(@decode_count).to eq(CHEESY_CACHE_FIXTURE_JPGS.size * 2 + 1)
    end
  end

  # --- §3.3 scenario 6: `rm -rf _site/` only -------------------------

  describe 'scenario 6: rm -rf _site/ only (cache kept)' do
    it 'skips Geometry pings but re-renders every variant' do
      build!
      FileUtils.rm_rf(dest_dir)
      FileUtils.mkdir_p(dest_dir)
      simulate_cold_process!
      reset_counters!
      build!

      expect(@ping_count).to   eq(0), 'Geometry cache survives; no pings needed'
      expect(@decode_count).to eq(CHEESY_CACHE_FIXTURE_JPGS.size * 2 + 1),
                               'Render cache says "rendered" but File.exist? is false → re-render'
    end
  end

  # --- §3.3 scenario 7: `rm -rf .jekyll-cache/` only -----------------

  describe 'scenario 7: rm -rf .jekyll-cache/ only (_site kept)' do
    # Expected = 4 (not 5) on a fixture with one gallery-index thumb:
    # the per-image `_thumb.jpg` and the per-gallery `_index.jpg` for
    # the same source share `ImageThumb.mtimes[path]`. Whichever
    # thumb writes second hits Layer A (`File.exist?(dest_path) &&
    # !modified?`) because the first one set mtimes[path] = mtime and
    # the dest files are still on disk from build 1. So one of the
    # two thumbs is silently skipped on the second build.
    it 'pings every source; re-renders every variant whose Layer A misses' do
      build!
      FileUtils.rm_rf(File.join(source_dir, '.jekyll-cache'))
      simulate_cold_process!
      reset_counters!
      build!

      expect(@ping_count).to   eq(CHEESY_CACHE_FIXTURE_JPGS.size)
      expect(@decode_count).to eq(CHEESY_CACHE_FIXTURE_JPGS.size * 2)
    end
  end

  # --- §3.3 scenario 8: jekyll serve --watch (in-process re-build) ---

  describe 'scenario 8: in-process re-build (jekyll serve --watch)' do
    it 'fires Layer A in the second cycle: no pings, no decodes' do
      build!
      # NB: NO simulate_cold_process! here — the whole point of this
      # scenario is that StaticFile.mtimes stays warm.
      reset_counters!
      build!

      expect(@ping_count).to   eq(0), 'Geometry cache still hits'
      expect(@decode_count).to eq(0), 'Layer A should have skipped every write'
    end
  end

  # --- §4 invalidation behaviour --------------------------------------

  describe '§4: invalidation behaviour' do
    it 'keys the Render cache on the absolute destination path' do
      build!
      keys = render_cache.instance_variable_get(:@cache).keys
      expect(keys.size).to eq(CHEESY_CACHE_FIXTURE_JPGS.size * 2 + 1)
      expect(keys).to all(start_with(dest_dir))
      expect(keys).to all(end_with('-rendered'))
    end

    it 'keys the Geometry cache on realpath + mtime + geometry' do
      build!
      keys = geometry_cache.instance_variable_get(:@cache).keys
      expect(keys.size).to eq(CHEESY_CACHE_FIXTURE_JPGS.size)
      keys.each do |k|
        realpath, mtime, geom = k.split('#', 3)
        expect(File.realdirpath(realpath)).to eq(realpath)
        expect(mtime).to match(%r{\A\d{4}-\d{2}-\d{2}})
        # The geometry component is the `geometry_string` that
        # ImageFile passes to `change_geometry!`, with the `>`
        # appended so we never upscale small originals.
        expect(geom).to eq('1920x1080>')
      end
    end

    it 'keys the Render cache on dest_path + source mtime + geometry' do
      build!
      keys = CheesyGallery::BaseImageFile
             .class_variable_get(:@@render_cache)
             .instance_variable_get(:@cache).keys
      image_file_keys = keys.reject { |k| k.include?('_thumb.jpg') || k.include?('_index.jpg') }
      expect(image_file_keys).not_to be_empty
      image_file_keys.each do |k|
        # Full-size renders include the geometry discriminator; thumbs
        # use the empty default and so look like the pre-discriminator
        # format. Both still end with `-rendered`.
        expect(k).to end_with('#1920x1080>-rendered')
      end
    end

    it 'Jekyll wipes our caches when _config.yml changes ' \
       '(via Jekyll::Cache.clear_if_config_changed)' do
      build!
      expect(render_cache_files).not_to be_empty

      # Touch _config.yml so its inspect digest changes. Jekyll's
      # `clear_if_config_changed`, called from Site#process, will
      # rm -rf the whole cache dir.
      File.write(File.join(source_dir, '_config.yml'), <<~YAML)
        collections:
          gallery:
            cheesy-gallery: true
            output: true
            quality: 50
        plugins: []
        quiet: true
      YAML

      simulate_cold_process!
      reset_counters!
      build!

      # Pings happened again because Geometry cache was wiped.
      # If the cache had survived, ping_count would be 0.
      expect(@ping_count).to eq(CHEESY_CACHE_FIXTURE_JPGS.size)
    end
  end

  # --- §5.1 path vs realpath ------------------------------------------

  describe '§5.1: path vs realpath via symlinked source (git-annex-like)' do
    it 'resolves symlinks for the geometry cache key' do
      # Replace one source with a symlink to a file in a separate
      # tree. This mimics how git-annex stores objects.
      target_dir = Dir.mktmpdir('cheesy-cache-spec-annex-')
      begin
        annex_object = File.join(target_dir, 'sha256e-abc.jpg')
        FileUtils.cp(File.join(CHEESY_CACHE_FIXTURE_DIR, CHEESY_CACHE_FIXTURE_JPGS.first), annex_object)
        symlink = File.join(source_dir, '_gallery', CHEESY_CACHE_FIXTURE_JPGS.first)
        FileUtils.rm(symlink)
        File.symlink(annex_object, symlink)

        build!
        cached_key = geometry_cache.instance_variable_get(:@cache).keys.first
        expect(cached_key).to include(annex_object),
                              'Geometry cache key should embed the realpath, not the symlink path'
      ensure
        FileUtils.remove_entry(target_dir, true)
      end
    end
  end

  # --- §5.5 ImageThumb never touches geometry cache ------------------

  describe '§5.5: ImageThumb does not consult the Geometry cache' do
    it 'pings exactly once per source, never for thumbnails' do
      build!
      # 2 sources, 5 variants (full+thumb+gallery thumb), but only 2 pings.
      expect(@ping_count).to eq(CHEESY_CACHE_FIXTURE_JPGS.size)
    end
  end

  # --- Run-to-run correctness: geometry cache returns right answers --

  describe 'Geometry cache correctness across simulated cold restarts' do
    it 'returns the same [height, width] tuple on hit as on first-miss' do
      build!
      first_run = geometry_cache.instance_variable_get(:@cache).dup
      simulate_cold_process!
      reset_counters!
      build!
      second_run = geometry_cache.instance_variable_get(:@cache)

      # Same keys, same values — proves Marshal round-trip is faithful.
      expect(second_run.keys.sort).to eq(first_run.keys.sort)
      first_run.each { |k, v| expect(second_run[k]).to eq(v) }
      expect(@ping_count).to eq(0)
    end
  end

  # --- Marshal corruption ---------------------------------------------

  describe 'Marshal corruption in a Geometry cache blob' do
    # The geometry cache uses `getset`, which rescues StandardError
    # (so Marshal.load failures look like a miss and recompute).
    it 'self-heals on the next build (rescue in getset)' do
      build!
      corrupt = geometry_cache_files.first
      expect(corrupt).not_to be_nil, 'fixture build should leave Geometry blobs on disk'
      File.write(corrupt, 'not a marshal blob')
      simulate_cold_process!
      reset_counters!
      expect { build! }.not_to raise_error
      # We expect a ping (Marshal.load raised → getset block ran).
      expect(@ping_count).to be >= 1
    end
  end

  describe 'Marshal corruption in a Render cache blob' do
    # The render cache check is `key? && File.exist?(dest_path)`.
    # `key?` only does `File.file? && File.readable?` — it does NOT
    # try to deserialise. So a corrupt blob still claims a hit and
    # the render is skipped. This is a real gotcha worth pinning
    # down in the suite.
    it 'is NOT self-healing: corrupt blob still suppresses re-render' do
      build!
      corrupt = render_cache_files.first
      File.write(corrupt, 'not a marshal blob')
      simulate_cold_process!
      reset_counters!
      expect { build! }.not_to raise_error
      expect(@decode_count).to eq(0),
                               'Render cache key? does not load the blob, so corruption is invisible'
    end
  end

  # --- StaticFile.mtimes is per-subclass -----------------------------

  describe '§1.1: StaticFile.mtimes is per-subclass (class-instance var)' do
    it 'has separate hashes for ImageFile and ImageThumb' do
      build!
      image_file_mtimes = CheesyGallery::ImageFile.mtimes
      image_thumb_mtimes = CheesyGallery::ImageThumb.mtimes
      expect(image_file_mtimes.object_id).not_to eq(image_thumb_mtimes.object_id),
                                                 'each subclass owns its own @mtimes (docs §1.1)'
      # Both contain the same source paths as keys, though, because
      # ImageThumb#path returns its @source_file.path (the ImageFile),
      # whose path returns the underlying source path.
      expect(image_file_mtimes.keys).to match_array(image_thumb_mtimes.keys)
    end
  end
end
