# frozen_string_literal: true

require 'rmagick'

# This StaticFile subclass adds additional functionality for images in the
# gallery
class CheesyGallery::ImageFile < Jekyll::StaticFile
  def initialize(site, collection, file)
    @source_file = file
    super(site, site.source, File.dirname(file.relative_path), file.name, collection)

    # read file metadata as it will be processed
    source = Magick::ImageList.new(path)
    source.change_geometry!('1920x1080') do |cols, rows, _img|
      data['height'] = rows
      data['width'] = cols
    end
  end

  # instead of copying, renders an optimised version
  def copy_file(dest_path)
    source = Magick::ImageList.new(path)
    nuimg = source.change_geometry!('1920x1080') do |cols, rows, img|
      img.resize!(cols, rows)
    end
    nuimg.write(dest_path) { self.quality = 50 }

    unless File.symlink?(dest_path) # rubocop:disable Style/GuardClause
      File.utime(self.class.mtimes[@source_file.path], self.class.mtimes[@source_file.path], dest_path)
    end
  end
end
