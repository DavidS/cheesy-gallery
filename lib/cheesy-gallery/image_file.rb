# frozen_string_literal: true

require 'rmagick'
require 'cheesy-gallery/base_image_file'

# This StaticFile subclass adds additional functionality for images in the
# gallery
class CheesyGallery::ImageFile < CheesyGallery::BaseImageFile
  @@geometry_cache = T.let(Jekyll::Cache.new('CheesyGallery::Geometry'), Jekyll::Cache) # don't need to worry about inheritance here # rubocop:disable Style/ClassVars

  sig { params(site: Jekyll::Site, collection: Jekyll::Collection, file: Jekyll::StaticFile, max_size: String, quality: Integer).void }
  def initialize(site, collection, file, max_size:, quality:)
    super(site, collection, file)

    @max_size = T.let(max_size, String)
    @quality = T.let(quality, Integer)

    realpath = File.realdirpath(path)
    mtime = File.mtime(realpath)
    geom = @@geometry_cache.getset("#{realpath}##{mtime}") do
      result = [100, 100]
      # read file metadata in the same way it will be processed
      Jekyll.logger.debug 'Identifying:', path
      source = Magick::Image.ping(path).first
      source.change_geometry!(@max_size) do |cols, rows, _img|
        result = [rows, cols]
      end
      source.destroy!
      result
    end

    data['height'] = geom[0]
    data['width'] = geom[1]
  end

  # instead of copying, renders an optimised version
  sig { params(img: Magick::ImageList, path: String).void }
  def process_and_write(img, path)
    img.change_geometry!(@max_size) do |cols, rows, i|
      i.resize!(cols, rows)
    end
    # follow recommendations from https://stackoverflow.com/a/7262050/4918 to get better compression
    img.interlace = Magick::PlaneInterlace
    # but skip the blur to avoid too many changes to the data
    # img.gaussian_blur(0.05)
    img.strip!
    # workaround weird {self} initialisation pattern
    quality = @quality
    img.write(path) { |image| image.quality = quality }
  end
end
