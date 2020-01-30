# typed: strict
# frozen_string_literal: true

require 'rmagick'

# This StaticFile subclass adds additional functionality for images in the
# gallery
class CheesyGallery::BaseImageFile < Jekyll::StaticFile
  extend T::Sig

  sig { params(site: Jekyll::Site, collection: Jekyll::Collection, file: Jekyll::StaticFile, dest_path: T.nilable(String)).void }
  def initialize(site, collection, file, dest_path = nil)
    @source_file = T.let(file, Jekyll::StaticFile)
    super(site, site.source, File.dirname(file.relative_path), dest_path || file.name, collection)
  end

  # use the source file's path for this, as this value is used all over the
  # place for mtime checking
  sig { returns String }
  def path
    @source_file.path
  end

  # overwrite this method to add additional processing
  sig { params(img: Magick::ImageList, path: String).void }
  def process_and_write(img, path)
    img.write(path) {}
  end

  private

  # instead of copying, allow rmagick processing
  # this is only called if the mtime doesn't match
  sig { params(dest_path: String).void }
  def copy_file(dest_path)
    source = Magick::ImageList.new(path)
    begin
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
