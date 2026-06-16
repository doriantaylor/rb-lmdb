require 'mkmf'

$CFLAGS << ' -std=c99 -Wall -g '
$CFLAGS << ' -fdeclspec' if /darwin/.match? RUBY_PLATFORM

dir_config('lmdb')

# --vendor flag: skip system lmdb and always build from vendored source
vendor_forced = arg_config('--vendor-lmdb', false)

have_system_lmdb = false

unless vendor_forced
  have_system_lmdb =
    have_header('lmdb.h') && have_library('lmdb', 'mdb_env_create')
end

unless have_system_lmdb
  vendor_dir = File.expand_path('../../vendor/liblmdb', __dir__)
  abort <<~MSG unless File.exist?(File.join(vendor_dir, 'mdb.c'))
    Could not find system lmdb and no vendored source found.
    Run `rake lmdb:fetch` to download the LMDB C source, then retry.
  MSG

  warn "Building from vendored LMDB source in #{vendor_dir}"
  $INCFLAGS << " -I#{vendor_dir}"
  $srcs = Dir[File.join(__dir__, '*.c')] +
          [File.join(vendor_dir, 'mdb.c'),
           File.join(vendor_dir, 'midl.c')]
  $VPATH << vendor_dir
end



have_header 'limits.h'
have_header 'string.h'
have_header 'stdlib.h'
have_header 'errno.h'
have_header 'sys/types.h'
have_header 'assert.h'

have_header 'ruby.h'

have_func 'rb_funcall_passing_block'
have_func 'rb_thread_call_without_gvl2'
have_func 'rb_gc_mark_movable'

create_header

create_makefile('lmdb_ext')
