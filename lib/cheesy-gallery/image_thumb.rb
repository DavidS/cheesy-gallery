# frozen_string_literal: true

require 'rmagick'

# This StaticFile subclass represents thumbnail images for each image. On `write()` it renders a 150x150 center crop of the source
class CheesyGallery::ImageThumb < Jekyll::StaticFile
  THUMB_POSTFIX = '_thumb.jpg'

  def initialize(site, collection, file)
    @source_file = file
    super(site, site.source, File.dirname(file.relative_path), file.name + THUMB_POSTFIX, collection)
  end

  # use the source file's path for this, as this value is used all over the
  # place for mtime checking
  def path
    @source_file.path
  end

  # instead of copying, renders the thumbnail
  # this is only called if the mtime doesn't match
  def copy_file(dest_path)
    source = Magick::ImageList.new(@source_file.path)
    nuimg = source.change_geometry!('150x150^') do |cols, rows, img|
      img.resize!(cols, rows)
      img.crop(Magick::CenterGravity, 150, 150)
    end
    nuimg.write(dest_path)

    unless File.symlink?(dest_path) # rubocop:disable Style/GuardClause
      File.utime(self.class.mtimes[@source_file.path], self.class.mtimes[@source_file.path], dest_path)
    end
  end
end
