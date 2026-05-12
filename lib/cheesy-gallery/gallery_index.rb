# frozen_string_literal: true

# This Document subclass is used to stand in for gallery indices which do not have a `index.html`
class CheesyGallery::GalleryIndex < Jekyll::Document
  DEFAULT_CONTENT = "This page intentionally left blank.\n"

  # No backing file exists — calling super would try File.read(path) and
  # abort the build. Mirror Jekyll::Document#read minus the file I/O.
  def read(_opts = {})
    merge_defaults
    self.content = DEFAULT_CONTENT
  end
end
