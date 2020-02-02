# typed: strict
# frozen_string_literal: true

require 'rmagick'
require 'cheesy-gallery/base_image_file'

# This StaticFile subclass represents thumbnail images for each image. On `write()` it renders a 150x150 center crop of the source
class CheesyGallery::ImageThumb < CheesyGallery::BaseImageFile
  sig { returns(Integer) }
  attr_reader :height, :width

  sig { params(site: Jekyll::Site, collection: Jekyll::Collection, file: Jekyll::StaticFile, postfix: String, height: Integer, width: Integer).void }
  def initialize(site, collection, file, postfix, height, width)
    super(site, collection, file, file.name + postfix)

    @height = T.let(height, Integer)
    @width = T.let(width, Integer)
  end

  # instead of copying, renders the thumbnail
  sig { params(img: Magick::ImageList, path: String).void }
  def process_and_write(img, path)
    img.resize_to_fill!(height, width)
    img.write(path) {}
  end
end
