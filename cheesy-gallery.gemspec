# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'cheesy-gallery/version'

Gem::Specification.new do |spec|
  spec.name          = 'cheesy-gallery'
  spec.version       = CheesyGallery::VERSION
  spec.authors       = ['David Schmitt']
  spec.email         = ['david@black.co.at']

  spec.summary       = 'A jekyll plugin for building galleries.'
  spec.homepage      = 'https://github.com/DavidS/cheesy-gallery'

  if spec.respond_to?(:metadata)
    spec.metadata['homepage_uri'] = spec.homepage
    spec.metadata['source_code_uri'] = 'https://github.com/DavidS/cheesy-gallery'
    spec.metadata['changelog_uri'] = 'https://github.com/DavidS/cheesy-gallery/blob/main/CHANGELOG.md'
  else
    raise 'RubyGems 2.0 or newer is required to set advanced metadata.'
  end

  spec.required_ruby_version = '>= 2.6.0'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 2.1'
  spec.add_development_dependency 'codecov'
  spec.add_development_dependency 'pry'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rubocop'

  spec.add_dependency 'jekyll', '~> 4.0'
  spec.add_dependency 'rmagick', '~> 4.0'
end
