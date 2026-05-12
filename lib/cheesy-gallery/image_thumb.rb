# frozen_string_literal: true

require 'vips'
require 'cheesy-gallery/base_image_file'

# This StaticFile subclass represents thumbnail images for each image. On `write()` it renders a 150x150 center crop of the source
class CheesyGallery::ImageThumb < CheesyGallery::BaseImageFile
  attr_reader :height, :width

  def initialize(site, collection, file, postfix, height, width)
    super(site, collection, file, file.name + postfix)

    @height = height
    @width = width
  end

  # centre-crop square thumbnail, optimised for file size at Q80
  def process_and_write(source_path, dest_path)
    img = Vips::Image.thumbnail(
      source_path,
      width,
      height: height,
      crop: :centre,
    )
    img.write_to_file(
      dest_path,
      Q: 80,
      interlace: true,
      keep: :none,
      optimize_coding: true,
      subsample_mode: :on,
    )
  end
end
