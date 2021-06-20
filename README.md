# Cheesy::Gallery

This is a jekyll photo gallery to manage large amounts of galleries and pictures. You can see the results at https://www.cheesy.at/fotos/.

## Installation

Follow Jekyll's documentation on [how to install plugins](https://jekyllrb.com/docs/plugins/installation/) using "cheesy-gallery" as name for the gem and plugin.

## Usage

After successful installation, enable gallery processing for a subdirectory of your site.
For this example, the folder is called `_my_gallery`:

```yaml
collections:
  my_gallery:
    cheesy-gallery: true
```

From now on, every Jekyll build will take all JPGs in all folders under `_my_gallery` and create a gallery for each folder, linking them according to their structure in the file system.

To add a thumbnail to a gallery, put it inside the gallery folder and call it `thumbnail.jpg`.

Frontmatter, like titles, etc., are read from the `index.md` file in the gallery.

Galleries and their contents are sorted by filename.

To layout galleries, check out the [example layout](spec/fixtures/test_site/_layouts/gallery.html) and adapt it to your site's style.

If you want an inline display of your photos, I recommend [glightbox](https://github.com/biati-digital/glightbox) by [biati-digital](https://github.com/biati-digital). Add their CSS and JavaScript to your assets, and link them in the `<head>` of your site:

```html
<link rel="stylesheet" href="{{ "/assets/glb/glightbox.min.css" | relative_url }}">
<script src="{{ "/assets/glb/glightbox.min.js" | relative_url }}"></script>
```

 Then, in the gallery layout, add `data-gallery="gallery"` attribute to the `<a>` tag linking to each image, and put

```html
<script type="text/javascript">
  const lightbox = GLightbox({selector: '*[data-gallery]'});
</script>
```

at the bottom of the layout.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment. There is also a test site in `spec/fixtures/test_site` that you can use to try out changes.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/DavidS/cheesy-gallery. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct. See [code of conduct](https://github.com/DavidS/cheesy-gallery/blob/main/CODE_OF_CONDUCT.md) for a local copy.
