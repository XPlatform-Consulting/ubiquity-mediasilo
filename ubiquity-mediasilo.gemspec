# coding: utf-8
lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)
require 'ubiquity/mediasilo/version'

Gem::Specification.new do |spec|
  spec.name          = 'ubiquity-mediasilo'
  spec.version       = Ubiquity::MediaSilo::VERSION
  spec.authors       = ['John Whitson']
  spec.email         = ['john.whitson@gmail.com']
  spec.homepage      = 'http://github.com/XPlatform-Consulting/ubiquity-mediasilo'
  spec.summary       = %q{A library to interact with MediaSilo.}
  spec.description   = %q{}

  spec.required_ruby_version     = '>= 1.8.7'

  spec.files         = `git ls-files -z`.split("\x0")
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})

  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'json'
  spec.add_development_dependency 'rspec', '~> 2.99.0.beta1'

end