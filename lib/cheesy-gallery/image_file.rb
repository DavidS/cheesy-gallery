# typed: strict
# frozen_string_literal: true

require 'rmagick'
require 'cheesy-gallery/base_image_file'

# This StaticFile subclass adds additional functionality for images in the
# gallery
class CheesyGallery::ImageFile < CheesyGallery::BaseImageFile
  sig { params(site: Jekyll::Site, collection: Jekyll::Collection, file: Jekyll::StaticFile, max_size: String, quality: Integer).void }
  def initialize(site, collection, file, max_size:, quality:)
    super(site, collection, file)

    @max_size = T.let(max_size, String)
    @quality = T.let(quality, Integer)

    # read file metadata in the same way it will be processed
    Jekyll.logger.debug 'Identifying:', path
    source = Magick::Image.ping(path).first
    source.change_geometry!(@max_size) do |cols, rows, _img|
      data['height'] = rows
      data['width'] = cols
    end
    source.destroy!
  end

  # instead of copying, renders an optimised version
  sig { params(img: Magick::ImageList, path: String).void }
  def process_and_write(img, path)
    img.change_geometry!(@max_size) do |cols, rows, i|
      i.resize!(cols, rows)
    end
    # workaround weird {self} initialisation pattern
    quality = @quality
    img.write(path) { self.quality = quality }
  end
end
