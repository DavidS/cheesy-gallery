# frozen_string_literal: true

# This Page subclass can be used to create new pages in the target site from scratch
class CheesyGallery::GalleryPage < Jekyll::Page
  ATTRIBUTES_FOR_LIQUID = (Jekyll::Page::ATTRIBUTES_FOR_LIQUID + %w[
    images
  ]).freeze

  def images
    @data['images'] ||= []
  end

  # Initialize a new Page.
  #
  # site - The Site object.
  # base - The String path to the source.
  # dir  - The String path between the source and the file.
  # name - The String filename of the file.
  def initialize(site, base, dir, name)
    # require 'pry'; binding.pry
    super(site, base, dir, name)
  end

  def read_yaml(base, name, opts = {})
    # puts "@path: #{@path}"
    # puts "base: #{base}"
    # puts "dir: #{dir}"
    # puts "name: #{name}"
    # puts "site.in_source_dir(base, name): #{site.in_source_dir(base, name)}"
    # puts ""
    super(base, name, opts) if File.exist?(@path)
    content = "DEFAULT GALLERY" if content.nil?
    @data ||= {} # ensure that there is a data hash, even if there is no source # rubocop:disable Naming/MemoizedInstanceVariableName
    # require 'pry'; binding.pry
  end

  def write(dest)
    puts "dest: #{dest}"
    puts "url: #{url}"
    puts "in_dest_dir: #{site.in_dest_dir(dest, Jekyll::URL.unescape_path(url))}"
    require'pry';binding.pry
    super(dest)
  end
end
