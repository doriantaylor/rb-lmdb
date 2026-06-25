require 'lmdb'
require 'rspec'
require 'fileutils'
require 'tmpdir'

# for valgrind
at_exit { GC.start }

TEMP_ROOT = File.join(Dir.tmpdir, 'lmdb-spec')

module LMDB::SpecHelper
  def mkpath(name = 'env')
    path = File.join(TEMP_ROOT, name)
    FileUtils.mkpath(path)
    path
  end

  def path
    @path ||= mkpath
  end

  def env
    @env ||= LMDB::Environment.new :path => path
  end
end

RSpec.configure do |c|
  c.include LMDB::SpecHelper
  c.after { FileUtils.rm_rf TEMP_ROOT }
  # c.expect_with :rspec do |cc|
  #   cc.syntax = :should
  # end
end
