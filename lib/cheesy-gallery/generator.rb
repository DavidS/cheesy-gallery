# frozen_string_literal: true

require 'jekyll'
require 'json'
require 'cheesy-gallery/gallery_index'
require 'cheesy-gallery/image_file'
require 'cheesy-gallery/image_thumb'

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
      doc.data['layout'] = 'gallery'
      collection.docs << doc if site.unpublished || doc.published?
    end

    # create replacements for the files with additional functionality
    image_files = collection.files.map do |f|
      CheesyGallery::ImageFile.new(site, collection, f)
    end

    # inject the `ImageFile`s into the collection
    image_files.each_with_index { |f, i| collection.files[i] = f }

    # collect files by gallery
    files_by_dirname = {}
    collection.files.each { |e| (files_by_dirname[File.dirname(e.relative_path)] ||= []) << e }

    # and galleries by their relative_path, after adding the Documents
    # only galleries named `index` can show up as parents
    galleries_by_dirname = {}
    collection.docs.find_all { |e| e.basename_without_ext == 'index' }.each { |e| galleries_by_dirname[File.dirname(e.relative_path)] = e }

    # this will be filled while linking up parents below
    # make sure each document has an entry, so later we can easily iterate everything
    galleries_by_parent = Hash[collection.docs.map { |d| [d, []] }]
    galleries_by_parent[nil] = []

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
      galleries_by_parent[parent] << doc

      # add thumbnail when there are images
      next if doc.data['images'].nil?

      collection.files << doc.data['thumbnail'] = CheesyGallery::ImageThumb.new(
        site,
        collection,
        doc.data['images'].first,
        '_index.jpg', 72, 72
      )
    end

    # link up sub-pages for tree navigation
    galleries_by_parent.each do |parent, pages|
      next if parent.nil?

      parent.data['pages'] = pages
    end

    # render image thumbnails and add them to the collection's files
    thumbs = image_files.map do |f|
      CheesyGallery::ImageThumb.new(site, collection, f)
    end

    collection.files.push(*thumbs)
  end
end
