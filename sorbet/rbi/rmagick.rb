# typed: true
# frozen_string_literal: true

class Magick::ImageList
  extend T::Sig

  sig { params(string: String, block: T.nilable(T.proc.params(arg0: Integer, arg1: Integer, arg2: Magick::Image).void)).void }
  def change_geometry!(string, &block); end

  sig { returns(NilClass) }
  def destroy!; end

  # the `info` block should be `T.nilable`, but https://github.com/sorbet/sorbet/issues/498 says "No!"
  sig { params(filename: String, info: T.proc.bind(Magick::Image::Info).void).void }
  def write(filename, &info); end
end
