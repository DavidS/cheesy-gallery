# typed: strong
# frozen_string_literal: true

require 'jekyll'
require 'fileutils'

# Main holder of all things cheesy and gallery-y
module CheesyGallery
  autoload :Generator, 'cheesy-gallery/generator'
end

# Liquid::Template.register_tag "gallery-link", CheesyGallery::GalleryLink
