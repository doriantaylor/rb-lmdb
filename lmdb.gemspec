
# -*- encoding: utf-8 -*-
require File.dirname(__FILE__) + '/lib/lmdb/version'
require 'date'

Gem::Specification.new do |s|
  s.name        = File.basename(__FILE__, '.gemspec')
  s.version     = LMDB::VERSION
  s.platform    = Gem::Platform::RUBY
  s.date        = Date.today.to_s
  s.licenses    = ['MIT']
  s.summary     = 'Ruby bindings to Lightning MDB'
  s.email       = 'code@doriantaylor.com'
  s.homepage    = 'https://github.com/doriantaylor/rb-lmdb'
  s.description = 'lmdb is a Ruby binding to OpenLDAP Lightning MDB.'
  s.authors     = ['Daniel Mendler', 'Dorian Taylor']
  s.extensions  = Dir['ext/**/extconf.rb']

  s.files         = `git ls-files --recurse-submodules -- *`.split("\n")
  s.test_files    = `git ls-files -- spec/*`.split("\n")
  s.require_paths = ['lib']

  s.required_ruby_version = '>= 2.7'

  s.add_development_dependency 'rake', '~> 13'
  s.add_development_dependency 'rake-compiler', '~> 1.2'
  s.add_development_dependency 'rspec', '~> 3'
  s.add_development_dependency 'ruby_memcheck', '~> 3'
end
