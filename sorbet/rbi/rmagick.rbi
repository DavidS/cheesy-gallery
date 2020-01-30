# typed: strong
# frozen_string_literal: true

# manual RBI definitions used by this project
class Magick::ImageList
  sig { params(string: String, block: T.nilable(T.proc.params(arg0: Integer, arg1: Integer, arg2: Magick::Image).void)).void }
  def change_geometry!(string, &block); end

  sig { returns(NilClass) }
  def destroy!; end

  sig { params(width: Integer, height: Integer, gravity: Magick::GravityType).returns(Magick::Image)}
  def resize_to_fill!(width, height, gravity=Magick::CenterGravity); end

  # the `info` block should be `T.nilable`, but https://github.com/sorbet/sorbet/issues/498 says "No!"
  sig { params(filename: String, info: T.proc.bind(Magick::Image::Info).void).void }
  def write(filename, &info); end
end
