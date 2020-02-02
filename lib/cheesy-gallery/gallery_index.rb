# typed: strict
# frozen_string_literal: true

# This Document subclass is used to stand in for gallery indices which do not have a `index.html`
class CheesyGallery::GalleryIndex < Jekyll::Document
  extend T::Sig

  DEFAULT_CONTENT = "This page intentionally left plank.\n"
  # skip reading content, as there is by definition no backing file for this
  sig { params(_opts: T.untyped).returns(String) }
  def read_content(_opts)
    self.content = DEFAULT_CONTENT
  end
end
