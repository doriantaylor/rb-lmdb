#!/usr/bin/env rake

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), "lib"))
GEMSPEC = Dir['*.gemspec'].first
PRJ = File.basename(GEMSPEC, ".gemspec")

require 'bundler/setup'
require 'rspec/core/rake_task'
require 'rake/extensiontask'
require 'ruby_memcheck'
require 'ruby_memcheck/rspec/rake_task'

RubyMemcheck.config(binary_name: 'lmdb_ext')

RSpec::Core::RakeTask.new :spec
Rake::ExtensionTask.new :lmdb_ext


task :default => [:compile, :spec]

namespace :spec do
  RubyMemcheck::RSpec::RakeTask.new(valgrind: :compile)
end

def version
  @version ||= begin
    require "#{PRJ}/version"
    warn "LMDB::VERSION not a string" unless LMDB::VERSION.kind_of? String
    LMDB::VERSION
  end
end

def tag
  @tag ||= "v#{version}"
end

def latest
  @latest ||= `git describe --abbrev=0 --tags --match 'v*'`.chomp
end

desc "Commit, tag, and push repo; build and push gem"
task :release => "release:is_new_version" do
  require 'tempfile'

  sh "gem build #{GEMSPEC}"

  file = Tempfile.new "template"
  begin
    file.puts "release #{version}"
    file.close
    sh "git commit --allow-empty -a -v -t #{file.path}"
  ensure
    file.close unless file.closed?
    file.unlink
  end

  sh "git tag #{tag}"
  sh "git push"
  sh "git push --tags"

  sh "gem push #{PRJ}-#{version}.gem"
end

namespace :release do
  desc "Diff to latest release"
  task :diff do
    sh "git diff #{latest}"
  end

  desc "Log to latest release"
  task :log do
    sh "git log #{latest}.."
  end

  task :is_new_version do
    abort "#{tag} exists; update version!" unless `git tag -l #{tag}`.empty?
  end
end

# all this business is to download actual releases of lmdb instead of using
# git submodules

require 'open-uri'
require 'json'
require 'fileutils'
require 'rubygems/package'
require 'zlib'

LMDB_VENDOR_DIR = File.expand_path('vendor/liblmdb', __dir__)
LMDB_NEEDED     = %w[mdb.c midl.c lmdb.h midl.h].freeze

namespace :lmdb do
  desc 'Fetch the latest LMDB C source into vendor/liblmdb'
  task :fetch do
    tags_url = 'https://api.github.com/repos/LMDB/lmdb/tags?per_page=20'
    headers  = { 'User-Agent' => 'rb-lmdb-gem-fetch' }

    tags = JSON.parse(URI.open(tags_url, headers).read)
    # warn tags.inspect
    # Tags are like "LMDB_0_9_32" — pick the highest numeric one
    tag  = tags
      .map { |t| t['name'] }
      .select { |n| n.match?(/\ALMDB_\d+[_.]\d+[_.]\d+\z/) }
      .max_by { |n| n.scan(/\d+/).map(&:to_i) }

    abort 'Could not determine latest LMDB tag' unless tag
    puts "Fetching LMDB #{tag}..."

    tarball_url = "https://github.com/LMDB/lmdb/archive/refs/tags/#{tag}.tar.gz"
    FileUtils.mkdir_p(LMDB_VENDOR_DIR)

    # Stream the tarball, extract only the liblmdb source files we need
    URI.open(tarball_url, headers) do |gz|
      Gem::Package::TarReader.new(Zlib::GzipReader.new(gz)).each do |entry|
        base = File.basename(entry.full_name)
        next unless entry.file? && LMDB_NEEDED.include?(base)
        dest = File.join(LMDB_VENDOR_DIR, base)
        File.write(dest, entry.read)
        puts "  -> #{dest}"
      end
    end

    File.write(File.join(LMDB_VENDOR_DIR, 'VERSION'), "#{tag}\n")
    puts "Done. LMDB #{tag} vendored in #{LMDB_VENDOR_DIR}."
  end
end
