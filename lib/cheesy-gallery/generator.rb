# frozen_string_literal: true

require 'jekyll'
require 'json'
require 'cheesy-gallery/gallery_index'

# The generator modifies the `site` data structure to contain all data necessary by the layouts and tags to render the galleries
class CheesyGallery::Generator < Jekyll::Generator
  def generate(site)
    @site = site
    collection = site.collections['galleries']

    # all galleries in the site
    galleries = Set[*collection.entries.map { |e| File.dirname(e) }]

    # all galleries with an index.html
    galleries_with_index = Set[*collection.entries.find_all { |e| e.end_with?('/index.html') }.map { |e| File.dirname(e) }]

    # fill in Documents for galleries that don't have an index.html
    (galleries - galleries_with_index).each do |e|
      doc = CheesyGallery::GalleryIndex.new(File.join('_galleries', e, 'index.html'), site: site, collection: collection)
      doc.read
      collection.docs << doc if site.unpublished || doc.published?
    end

    files_by_dirname = {}
    collection.files.each { |e| (files_by_dirname[File.dirname(e.relative_path)] ||= []) << e }

    collection.docs.each do |doc|
      # attach images
      doc.data['images'] = files_by_dirname[File.dirname(doc.relative_path)]
    end
  end
end
