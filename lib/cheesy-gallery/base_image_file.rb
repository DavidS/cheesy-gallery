# frozen_string_literal: true

require 'rmagick'

# This StaticFile subclass adds additional functionality for images in the
# gallery
class CheesyGallery::BaseImageFile < Jekyll::StaticFile
  @@render_cache = Jekyll::Cache.new('CheesyGallery::Render') # don't need to worry about inheritance here # rubocop:disable Style/ClassVars

  def initialize(site, collection, file, dest_path = nil)
    @source_file = file
    super(site, site.source, File.dirname(file.relative_path), dest_path || file.name, collection)
  end

  # use the source file's path for this, as this value is used all over the
  # place for mtime checking
  def path
    @source_file.path
  end

  # overwrite this method to add additional processing
  def process_and_write(img, path)
    img.write(path) {}
  end

  # Skip the render when our content-aware Render-cache key says we've
  # already produced this exact (dest, source-mtime) pair and the
  # destination is still on disk. Otherwise defer to Jekyll's StaticFile
  # write, which handles the modified? check, mkdir_p, rm of an existing
  # dest, and the call to our overridden copy_file below.
  def write(dest)
    dest_path = destination(dest)
    if File.exist?(dest_path) && @@render_cache.key?(render_cache_key(dest_path))
      self.class.mtimes[path] = mtime
      return false
    end

    super
  end

  private

  # Render-cache key is dest_path plus source mtime so that an in-place
  # source edit (or a re-pointed git-annex symlink) invalidates the
  # cached marker naturally. Stale entries under old keys linger on
  # disk until `jekyll clean`; cosmetic.
  def render_cache_key(dest_path)
    "#{dest_path}##{mtime.to_i}-rendered"
  end

  # Replace Jekyll's StaticFile#copy_file (FileUtils.cp) with RMagick
  # rendering. Super's write has already mkdir_p'd the parent and
  # rm'd any existing dest_path before getting here.
  def copy_file(dest_path)
    source = Magick::ImageList.new(path)
    begin
      Jekyll.logger.debug 'Rendering:', dest_path
      process_and_write(source, dest_path)
    ensure
      source.destroy!
    end

    unless File.symlink?(dest_path)
      File.utime(self.class.mtimes[path], self.class.mtimes[path], dest_path)
    end

    @@render_cache[render_cache_key(dest_path)] = true
  end
end
