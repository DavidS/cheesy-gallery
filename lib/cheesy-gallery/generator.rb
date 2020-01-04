# frozen_string_literal: true

require 'jekyll'
require 'cheesy-gallery/utils'

# The generator modifies the `site` data structure to contain all data necessary by the layouts and tags to render the galleries
class CheesyGallery::Generator < Jekyll::Generator
  def generate(site)
    @site = site

    galleries = collect_galleries(site.source, '_galleries')

    debug_page = make_page('debug.html')
    debug_page.content = "debug\n"
    site.pages << debug_page
    # read `_galleries`
    # modify `site`
  end

  def collect_galleries(base_dir, next_dir)
    (Dir.foreach(File.join(base_dir, next_dir)).collect do |entry|
      next if ['.', '..'].include?(entry)

      path = File.join(next_dir, entry)
      full_path = File.join(base_dir, path)
      next unless File.directory?(full_path)

      collect_galleries(base_dir, path) + [
        {
          name: entry,
          source: full_path,
        },
      ]
    end || []).flatten.find_all { |f| !f.nil? }
  end

  def make_page(file_path, collection: 'posts', category: nil)
    PageWithoutAFile.new(@site, __dir__, '', file_path).tap do |file|
      # file.content = "feed_template\n"
      file.data.merge!(
        'layout' => 'debug',
        'sitemap' => false,
        'collection' => collection,
        'category' => category,
      )
      file.output
    end
  end
end
