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

    # collect files by gallery
    files_by_dirname = {}
    collection.files.each { |e| (files_by_dirname[File.dirname(e.relative_path)] ||= []) << e }

    # and galleries by their relative_path, after adding the Documents
    # only galleries named `index` can show up as parents
    galleries_by_dirname = {}
    collection.docs.find_all { |e| e.basename_without_ext == 'index' }.each { |e| galleries_by_dirname[File.dirname(e.relative_path)] = e }

    collection.docs.each do |doc|
      gallery_path = File.dirname(doc.relative_path)

      # attach images
      doc.data['images'] = files_by_dirname[gallery_path]

      # attach parent
      parent = if gallery_path == '_galleries/.'
                 # main gallery doesn't have parent
                 nil
               elsif File.dirname(gallery_path) == '_galleries'
                 # main gallery has a weird relative_path
                 galleries_by_dirname['_galleries/.']
               else
                 # everyone else is regular
                 galleries_by_dirname[File.dirname(gallery_path)]
               end
      doc.data['parent'] = parent
    end
  end
end
