# frozen_string_literal: true

require 'jekyll'
require 'json'
require 'cheesy-gallery/utils'

# The generator modifies the `site` data structure to contain all data necessary by the layouts and tags to render the galleries
class CheesyGallery::Generator < Jekyll::Generator
  def generate(site)
    @site = site

    galleries = collect_galleries(File.join(site.source, '_galleries'), File.join(site.dest, 'galleries'))

    debug_page = make_gallery_page("nil", 'debug.html')
    debug_page.content = JSON.pretty_generate(galleries)
    site.pages << debug_page

    galleries.each do |g|
      site.pages << make_gallery_page(File.join(g[:path], 'index.html'), File.join(g[:dest], 'index.html'))
    end

    # read `_galleries`
    # modify `site`
  end

  # source_dir: join(site.source, config[:gallery][:source] = '_galleries')
  # dest_dir: join(site.dest, config[:gallery][:dest] = 'galleries' )
  # next_dir: relative path within the gallery tree, used in recursion, leave `nil` for first level
  def collect_galleries(source_dir, dest_dir, next_dir = nil)
    if next_dir.nil?
      current_dir = source_dir
      next_dir = '/'
    else
      current_dir = File.join(source_dir, next_dir)
    end

    (Dir.foreach(current_dir).collect do |entry|
      # skip self and parent directory
      next if ['.', '..'].include?(entry)

      path = File.join(next_dir, entry)

      # files (as opposed to directories) will be handled later
      source_path = File.join(source_dir, path)
      next unless File.directory?(source_path)

      dest_path = File.join(dest_dir, path)

      collect_galleries(source_dir, dest_dir, path) + [
        {
          name: entry,
          path: path,
          source: source_path,
          dest: dest_path,
        },
      ]
    end || []).flatten.find_all { |f| !f.nil? }
  end

  def make_gallery_page(source_path, target_path)
    CheesyGallery::PageWithoutAFile.new(@site, __dir__, '', target_path).tap do |file|
      # file.content = "feed_template\n"
      file.data.merge!(
        'layout' => 'debug',
        'sitemap' => false,
        'source' => source_path,
      )
      file.output
    end
  end
end
