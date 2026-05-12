# frozen_string_literal: true

require 'spec_helper'
require 'jekyll'
require 'fileutils'
require 'tmpdir'
require 'rmagick'

# Plugin-behaviour specs covering docs/todos.md §4: end-to-end site
# generation, the synthetic GalleryIndex doc for index-less gallery
# directories, parent/child wiring, thumbnail selection, image
# dimension extraction, and the `max_size` / `quality` collection
# metadata overrides.
#
# Each example builds a fresh ephemeral Jekyll site under a tmpdir
# (mirroring spec/cheesy/cache_spec.rb) so we don't depend on — or
# pollute — the canonical spec/fixtures/test_site tree, and so the
# collection layouts can be tailored per scenario.
FIXTURE_JPG_DIR = File.expand_path('../fixtures/test_site/_gallery_two', __dir__)

# Source path lookup for the small (~1000x750) JPGs the spec
# fixtures pull in. The Frostig pair lives directly under
# _gallery_two/, the Morgenspaziergang pair under _gallery_two/third/.
FIXTURE_JPGS = {
  'Frostig-001.jpg' => File.join(FIXTURE_JPG_DIR, 'Frostig-001.jpg'),
  'Frostig-003.jpg' => File.join(FIXTURE_JPG_DIR, 'Frostig-003.jpg'),
  'Morgenspaziergang-2.jpg' => File.join(FIXTURE_JPG_DIR, 'third', 'Morgenspaziergang-2.jpg'),
  'Morgenspaziergang-3.jpg' => File.join(FIXTURE_JPG_DIR, 'third', 'Morgenspaziergang-3.jpg'),
}.freeze

RSpec.describe CheesyGallery::Generator do
  let(:source_dir) { Dir.mktmpdir('cheesy-gen-spec-src-') }
  let(:dest_dir)   { Dir.mktmpdir('cheesy-gen-spec-dest-') }

  before { simulate_cold_process! }

  after do
    FileUtils.remove_entry(source_dir, true) if File.exist?(source_dir)
    FileUtils.remove_entry(dest_dir,   true) if File.exist?(dest_dir)
    simulate_cold_process!
  end

  # --- helpers --------------------------------------------------------

  # Drop in-memory cache state between examples so we don't accidentally
  # hit blobs left behind by a previous tmpdir. The on-disk cache lives
  # under each spec's own source tree, so nothing else needs clearing.
  def simulate_cold_process!
    Jekyll::StaticFile.reset_cache
    [CheesyGallery::BaseImageFile, CheesyGallery::ImageFile, CheesyGallery::ImageThumb].each do |k|
      k.reset_cache if k.respond_to?(:reset_cache)
    end
    {
      CheesyGallery::BaseImageFile => :@@render_cache,
      CheesyGallery::ImageFile => :@@geometry_cache,
    }.each do |klass, ivar|
      next unless klass.class_variable_defined?(ivar)

      cache = klass.class_variable_get(ivar)
      cache.instance_variable_get(:@cache).clear
      cache.instance_variable_set(:@base_dir, nil)
    end
  end

  def build!
    config = Jekyll.configuration(
      'source' => source_dir, 'destination' => dest_dir,
      'plugins' => [], 'quiet' => true
    )
    site = Jekyll::Site.new(config)
    site.process
    site
  end

  def write_layout!
    FileUtils.mkdir_p(File.join(source_dir, '_layouts'))
    File.write(File.join(source_dir, '_layouts', 'gallery.html'), "---\n---\n{{ content }}\n")
  end

  def write_config!(yaml)
    File.write(File.join(source_dir, '_config.yml'), yaml)
  end

  def write_explicit_index!(rel_dir)
    target = File.join(source_dir, rel_dir, 'index.html')
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, "---\nlayout: gallery\n---\n")
  end

  def cp_jpg!(name, rel_dir, dest_name: nil)
    target = File.join(source_dir, rel_dir, dest_name || File.basename(name))
    FileUtils.mkdir_p(File.dirname(target))
    FileUtils.cp(FIXTURE_JPGS.fetch(name), target)
  end

  # Default fixture: two collections matching the structure of the
  # canonical spec/fixtures/test_site. _gallery_one has its own
  # index.html; _gallery_two has none (synthetic), plus a `third/`
  # subgallery with its own index.html.
  def write_two_gallery_fixture!
    write_config!(<<~YAML)
      collections:
        gallery_one:
          cheesy-gallery: true
          gallery_thumbnail_size: 150
          image_thumbnail_size: 150
          quality: 70
        gallery_two:
          cheesy-gallery: true
          max_size: 600x400
      plugins: []
      quiet: true
    YAML
    write_layout!
    write_explicit_index!('_gallery_one')
    cp_jpg!('Frostig-001.jpg', '_gallery_one')
    cp_jpg!('Frostig-003.jpg', '_gallery_one')
    cp_jpg!('Frostig-001.jpg', '_gallery_two')
    cp_jpg!('Frostig-003.jpg', '_gallery_two')
    write_explicit_index!('_gallery_two/third')
    cp_jpg!('Morgenspaziergang-2.jpg', '_gallery_two/third')
    cp_jpg!('Morgenspaziergang-3.jpg', '_gallery_two/third')
  end

  # --- end-to-end build ----------------------------------------------

  describe 'end-to-end Jekyll::Site#process' do
    it 'writes full-size images for every source JPG' do
      write_two_gallery_fixture!
      build!

      %w[
        gallery_one/Frostig-001.jpg
        gallery_one/Frostig-003.jpg
        gallery_two/Frostig-001.jpg
        gallery_two/Frostig-003.jpg
        gallery_two/third/Morgenspaziergang-2.jpg
        gallery_two/third/Morgenspaziergang-3.jpg
      ].each do |rel|
        expect(File).to exist(File.join(dest_dir, rel)), "missing rendered #{rel}"
      end
    end

    it 'writes a *_thumb.jpg next to every source JPG' do
      write_two_gallery_fixture!
      build!

      thumbs = Dir.glob(File.join(dest_dir, '**', '*_thumb.jpg'))
      expect(thumbs.size).to eq(6)
    end

    it 'writes one *_index.jpg per gallery' do
      write_two_gallery_fixture!
      build!

      index_thumbs = Dir.glob(File.join(dest_dir, '**', '*_index.jpg'))
      expect(index_thumbs.size).to eq(3)
      expect(index_thumbs.map { |p| File.dirname(p).sub("#{dest_dir}/", '') })
        .to match_array(%w[gallery_one gallery_two gallery_two/third])
    end

    it 'writes an index.html for every gallery (explicit and synthetic)' do
      write_two_gallery_fixture!
      build!

      %w[gallery_one gallery_two gallery_two/third].each do |g|
        expect(File).to exist(File.join(dest_dir, g, 'index.html')), "missing #{g}/index.html"
      end
    end
  end

  # --- synthetic GalleryIndex ----------------------------------------

  describe 'synthetic GalleryIndex for directories without an index.html' do
    let(:site) do
      write_two_gallery_fixture!
      build!
    end

    let(:synthetic) { site.collections['gallery_two'].docs.find { |d| d.url == '/gallery_two/index.html' } }
    let(:explicit)  { site.collections['gallery_one'].docs.find { |d| d.url == '/gallery_one/index.html' } }

    it 'creates a CheesyGallery::GalleryIndex for gallery_two/' do
      expect(synthetic).to be_a(CheesyGallery::GalleryIndex)
    end

    it 'forces layout=gallery on the synthetic doc' do
      expect(synthetic.data['layout']).to eq('gallery')
    end

    it 'uses the placeholder content (no backing file to read)' do
      expect(synthetic.content).to eq(CheesyGallery::GalleryIndex::DEFAULT_CONTENT)
    end

    it 'leaves explicit index.html docs as a plain Jekyll::Document' do
      expect(explicit).to be_a(Jekyll::Document)
      expect(explicit).not_to be_a(CheesyGallery::GalleryIndex)
    end

    it 'does not create a synthetic doc for galleries that already have an index.html' do
      synthetics_in_gallery_one = site.collections['gallery_one'].docs.grep(CheesyGallery::GalleryIndex)
      expect(synthetics_in_gallery_one).to be_empty
    end
  end

  # --- parent / child wiring -----------------------------------------

  describe 'parent / child wiring' do
    let(:site) do
      write_two_gallery_fixture!
      build!
    end

    let(:gallery_one_root) { site.collections['gallery_one'].docs.find { |d| d.url == '/gallery_one/index.html' } }
    let(:gallery_two_root) { site.collections['gallery_two'].docs.find { |d| d.url == '/gallery_two/index.html' } }
    let(:gallery_two_third) { site.collections['gallery_two'].docs.find { |d| d.url == '/gallery_two/third/index.html' } }

    it 'attaches no parent to a root gallery' do
      expect(gallery_one_root.data['parent']).to be_nil
      expect(gallery_two_root.data['parent']).to be_nil
    end

    it 'attaches the root gallery as parent of a nested subgallery' do
      expect(gallery_two_third.data['parent']).to eq(gallery_two_root)
    end

    it 'lists nested subgalleries under the parent doc\'s data[\'pages\']' do
      expect(gallery_two_root.data['pages']).to include(gallery_two_third)
    end

    it 'gives leaf galleries an empty pages list' do
      expect(gallery_one_root.data['pages']).to eq([])
      expect(gallery_two_third.data['pages']).to eq([])
    end
  end

  # --- thumbnail selection -------------------------------------------

  describe 'thumbnail selection' do
    it 'prefers an explicit thumbnail.jpg over the first image' do
      write_config!(<<~YAML)
        collections:
          gallery:
            cheesy-gallery: true
        plugins: []
        quiet: true
      YAML
      write_layout!
      write_explicit_index!('_gallery')
      cp_jpg!('Frostig-001.jpg', '_gallery')
      cp_jpg!('Frostig-003.jpg', '_gallery', dest_name: 'thumbnail.jpg')
      site = build!

      doc = site.collections['gallery'].docs.find { |d| d.url == '/gallery/index.html' }
      expect(doc.data['thumbnail_source'].name).to eq('thumbnail.jpg')
      expect(doc.data['images'].map(&:name)).not_to include('thumbnail.jpg')
    end

    it 'falls back to the alphabetically-first image when no thumbnail.jpg exists' do
      write_config!(<<~YAML)
        collections:
          gallery:
            cheesy-gallery: true
        plugins: []
        quiet: true
      YAML
      write_layout!
      write_explicit_index!('_gallery')
      cp_jpg!('Frostig-001.jpg', '_gallery', dest_name: 'b.jpg')
      cp_jpg!('Frostig-003.jpg', '_gallery', dest_name: 'a.jpg')
      site = build!

      doc = site.collections['gallery'].docs.find { |d| d.url == '/gallery/index.html' }
      expect(doc.data['thumbnail_source'].name).to eq('a.jpg')
    end

    it 'attaches no thumbnail when the gallery has no images' do
      write_config!(<<~YAML)
        collections:
          gallery:
            cheesy-gallery: true
        plugins: []
        quiet: true
      YAML
      write_layout!
      write_explicit_index!('_gallery')
      site = build!

      doc = site.collections['gallery'].docs.find { |d| d.url == '/gallery/index.html' }
      expect(doc.data['thumbnail_source']).to be_nil
      expect(doc.data['thumbnail']).to be_nil
      expect(Dir.glob(File.join(dest_dir, 'gallery', '*_index.jpg'))).to be_empty
    end
  end

  # --- image dimension extraction ------------------------------------

  describe 'image dimension extraction' do
    it 'leaves source dimensions alone when smaller than max_size (shrink-only)' do
      write_two_gallery_fixture!
      site = build!

      # 1000x750 source under default max_size '1920x1080'.
      # ImageFile appends `>` so change_geometry! only shrinks
      # originals larger than the box; smaller ones pass through
      # unchanged.
      frostig = site.collections['gallery_one'].files.find do |f|
        f.is_a?(CheesyGallery::ImageFile) && f.name == 'Frostig-001.jpg'
      end
      expect([frostig.data['width'], frostig.data['height']]).to eq([1000, 750])
    end

    it 'reflects the max_size override in data dimensions' do
      write_two_gallery_fixture!
      site = build!

      # 1000x750 source under max_size '600x400' → 533x400.
      frostig = site.collections['gallery_two'].files.find do |f|
        f.is_a?(CheesyGallery::ImageFile) && f.name == 'Frostig-001.jpg'
      end
      expect([frostig.data['width'], frostig.data['height']]).to eq([533, 400])
    end
  end

  # --- max_size / quality overrides ----------------------------------

  describe 'collection-metadata overrides' do
    it 'shrinks the rendered output to fit the configured max_size' do
      write_two_gallery_fixture!
      build!

      out = Magick::Image.ping(File.join(dest_dir, 'gallery_two', 'Frostig-001.jpg')).first
      begin
        expect(out.columns).to be <= 600
        expect(out.rows).to be <= 400
      ensure
        out.destroy!
      end
    end

    it 'leaves rendered output at source size when below the default max_size' do
      write_two_gallery_fixture!
      build!

      # Shrink-only `>` policy: 1000x750 stays 1000x750 under the
      # default '1920x1080' max_size.
      out = Magick::Image.ping(File.join(dest_dir, 'gallery_one', 'Frostig-001.jpg')).first
      begin
        expect([out.columns, out.rows]).to eq([1000, 750])
      ensure
        out.destroy!
      end
    end

    it 'passes max_size and quality through from collection metadata to ImageFile' do
      write_two_gallery_fixture!
      site = build!

      from_one = site.collections['gallery_one'].files.find do |f|
        f.is_a?(CheesyGallery::ImageFile) && f.name == 'Frostig-001.jpg'
      end
      from_two = site.collections['gallery_two'].files.find do |f|
        f.is_a?(CheesyGallery::ImageFile) && f.name == 'Frostig-001.jpg'
      end

      expect(from_one.instance_variable_get(:@max_size)).to eq('1920x1080')
      expect(from_one.instance_variable_get(:@quality)).to eq(70)
      expect(from_two.instance_variable_get(:@max_size)).to eq('600x400')
      # gallery_two doesn't override quality → default of 85
      expect(from_two.instance_variable_get(:@quality)).to eq(85)
    end
  end
end
