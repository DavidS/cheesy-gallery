# typed: strict
# frozen_string_literal: true

require 'jekyll'
require 'json'
require 'cheesy-gallery/gallery_index'
require 'cheesy-gallery/image_file'
require 'cheesy-gallery/image_thumb'

# The generator modifies the `site` data structure to contain all data necessary by the layouts and tags to render the galleries
class CheesyGallery::Generator < Jekyll::Generator
  extend T::Sig

  sig { params(site: Jekyll::Site).void }
  def generate(site)
    @site = T.let(site, T.nilable(Jekyll::Site))
    (site.collections.values.find_all { |c| c.metadata['cheesy-gallery'] } || [site.collections['galleries']]).compact.each do |collection|
      collection.metadata['output'] = true unless collection.metadata.key? 'output'

      # all directories in the collection that have a file in them, as absolute paths from the root of the collection
      galleries = Set[*collection.entries.map { |e| File.expand_path(File.join('/', File.dirname(e))) }]

      # all directories in the collection that have an 'index' in them, as absolute paths from the root of the collection
      galleries_with_index = Set[*collection.docs.find_all { |e| e.basename_without_ext == 'index' }.map { |e| File.dirname(e.cleaned_relative_path) }]

      # fill in Documents for galleries that don't have an index
      (galleries - galleries_with_index).each do |e|
        doc = CheesyGallery::GalleryIndex.new(File.join(collection.relative_directory, e, 'index.html'), site: site, collection: collection)
        doc.read
        doc.data['layout'] = 'gallery'
        collection.docs << doc if site.unpublished || doc.published?
      end

      # create replacements for the files with additional functionality
      image_files = collection.files.sort { |a, b| a.name <=> b.name }.map do |f|
        CheesyGallery::ImageFile.new(
          site, collection, f,
          max_size: collection.metadata['max_size'] || '1920x1080',
          quality: collection.metadata['quality'] || 50
        )
      end

      # inject the `ImageFile`s into the collection
      image_files.each_with_index { |f, i| collection.files[i] = f }

      # collect files by gallery
      files_by_dirname = {}
      collection.files.each { |e| (files_by_dirname[File.dirname(e.relative_path)] ||= []) << e }

      # and galleries by their relative_path, after adding the Documents
      # only documents named `index` can show up as parent galleries
      galleries_by_dirname = {}
      collection.docs.find_all { |e| e.basename_without_ext == 'index' }.each { |e| galleries_by_dirname[File.dirname(e.relative_path)] = e }

      # this will be filled while linking up parents below
      # make sure each document has an entry, so later we can easily iterate everything
      galleries_by_parent = Hash[collection.docs.map { |d| [d, []] }]
      galleries_by_parent[nil] = []

      collection.docs.each do |doc|
        gallery_path = File.dirname(doc.relative_path)
        # fix up '_galleries/.' path of root index
        if gallery_path == File.join(collection.relative_directory, '.')
          gallery_path = collection.relative_directory
        end

        # attach images
        doc.data['images'] = files_by_dirname[gallery_path]
        doc.data['thumbnail_source'] = doc.data['images']&.select { |i| i.name == 'thumbnail.jpg' }&.first || doc.data['images']&.first
        doc.data['images']&.reject! { |i| i.name == 'thumbnail.jpg' }

        # attach parent
        parent = if gallery_path == collection.relative_directory
                   # root gallery doesn't have a parent
                   nil
                 else
                   galleries_by_dirname[File.dirname(gallery_path)]
                 end
        doc.data['parent'] = parent
        galleries_by_parent[parent] << doc

        # only add thumbnail when there is a thumbnail source
        next unless doc.data['thumbnail_source']

        collection.files << doc.data['thumbnail'] = CheesyGallery::ImageThumb.new(
          site,
          collection,
          doc.data['thumbnail_source'],
          '_index.jpg',
          collection.metadata['gallery_thumbnail_size'] || 72,
          collection.metadata['gallery_thumbnail_size'] || 72,
        )
      end

      # link up sub-pages for tree navigation
      galleries_by_parent.each do |parent, pages|
        next if parent.nil?

        parent.data['pages'] = pages
      end

      # render image thumbnails and add them to the collection's files
      thumbs = image_files.map do |f|
        CheesyGallery::ImageThumb.new(
          site, collection, f,
          '_thumb.jpg',
          collection.metadata['image_thumbnail_size'] || 150,
          collection.metadata['image_thumbnail_size'] || 150
        )
      end

      collection.files.push(*thumbs)

      # sort files by source path, so that we have better cache hits when reading from disk
      # with more effort files could share the Magick::ImageList instance, but destroying those
      # at the right time to stay within Magick's cache policy would be awkward at best
      collection.files.sort! { |a, b| a.path <=> b.path }
    end
  end
end
