# typed: false
# frozen_string_literal: true

require 'rmagick'

# This StaticFile subclass adds additional functionality for images in the
# gallery
class CheesyGallery::BaseImageFile < Jekyll::StaticFile
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
    img.write(path)
  end

  private

  # instead of copying, allow rmagick processing
  # this is only called if the mtime doesn't match
  def copy_file(dest_path)
    begin
      source = Magick::ImageList.new(path)
      Jekyll.logger.debug 'Rendering:', dest_path
      process_and_write(source, dest_path)
    ensure
      # clean up cache
      source.destroy!
    end

    unless File.symlink?(dest_path) # rubocop:disable Style/GuardClause
      File.utime(self.class.mtimes[@source_file.path], self.class.mtimes[@source_file.path], dest_path)
    end
  end
end
