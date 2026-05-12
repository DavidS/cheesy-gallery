# frozen_string_literal: true

require 'vips'
require 'cheesy-gallery/base_image_file'

# This StaticFile subclass adds additional functionality for images in the
# gallery
class CheesyGallery::ImageFile < CheesyGallery::BaseImageFile
  @@geometry_cache = Jekyll::Cache.new('CheesyGallery::Geometry') # don't need to worry about inheritance here # rubocop:disable Style/ClassVars

  def initialize(site, collection, file, max_size:, quality:)
    super(site, collection, file)

    @max_size = max_size
    @quality = quality

    realpath = File.realdirpath(path)
    mtime = File.mtime(realpath)
    @geometry = @@geometry_cache.getset("#{realpath}##{mtime}##{geometry_string}") do
      Jekyll.logger.debug 'Identifying:', path
      # autorot so width/height reflect post-orientation pixels — matches
      # what Vips::Image.thumbnail will produce at render time.
      source = Vips::Image.new_from_file(path, access: :sequential, fail_on: :error).autorot
      fit_inside(source.width, source.height)
    end

    data['height'] = @geometry[0]
    data['width'] = @geometry[1]
  end

  # instead of copying, renders an optimised version
  def process_and_write(source_path, dest_path)
    target_h, target_w = @geometry
    img = Vips::Image.thumbnail(
      source_path,
      target_w,
      height: target_h,
      size: :down, # never upscale — equivalent of the `>` in geometry_string
      crop: :none,
    )
    img.write_to_file(
      dest_path,
      Q: @quality,
      interlace: true,
      keep: :none,
      optimize_coding: true,
      subsample_mode: :on,
    )
  end

  private

  # Preserved from the RMagick era. Under libvips this is no longer
  # passed to an image library — its value is purely the cache
  # fingerprint so that changing `max_size` (or upgrading to a release
  # that changes the upscale policy) invalidates entries naturally.
  # Idempotent: skip the `>` append if the user already supplied any
  # ImageMagick geometry flag (!, <, >, ^, @, #).
  def geometry_string
    @geometry_string ||= @max_size.match?(%r{[!<>^@#]}) ? @max_size : "#{@max_size}>"
  end

  # Mix the geometry into the Render-cache key so changing the
  # `max_size` config (or upgrading to a release that changes the
  # upscale policy) invalidates stale rendered outputs.
  def render_cache_discriminator
    geometry_string
  end

  # Replicates the shrink-only `WxH>` semantics that the geometry
  # string previously got from ImageMagick: fit inside the box,
  # preserve aspect ratio, never upscale. Returns [height, width] to
  # match the legacy Geometry-cache shape and the data hash. The
  # ImageMagick-style trailing flags (`!`, `^`, `@`, `#`) are parsed
  # out by `to_i`'s leading-digits rule and silently ignored — see
  # CHANGELOG for the narrowing.
  def fit_inside(src_width, src_height)
    max_w, max_h = @max_size.split('x').map(&:to_i)
    scale = [max_w.to_f / src_width, max_h.to_f / src_height, 1.0].min
    [(src_height * scale).round, (src_width * scale).round]
  end
end
