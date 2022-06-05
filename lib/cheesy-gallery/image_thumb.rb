# frozen_string_literal: true

require 'rmagick'
require 'cheesy-gallery/base_image_file'

# This StaticFile subclass represents thumbnail images for each image. On `write()` it renders a 150x150 center crop of the source
class CheesyGallery::ImageThumb < CheesyGallery::BaseImageFile
  attr_reader :height, :width

  def initialize(site, collection, file, postfix, height, width)
    super(site, collection, file, file.name + postfix)

    @height = height
    @width = width
  end

  # instead of copying, renders the thumbnail
  def process_and_write(img, path)
    img.resize_to_fill!(height, width)
    img.write(path)
  end
end
