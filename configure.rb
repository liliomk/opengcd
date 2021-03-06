#!/usr/bin/env ruby
#
# Copyright (c) 2012 Mark Heily <mark@heily.com>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
# 
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
#

$LOAD_PATH << 'makeconf'

require 'makeconf'

# Return an authenticated or anonymous SVN URI
def svn(path)
  if ENV['USER'] == 'mheily'
    'svn+ssh://heily.com/home/mheily/svn/' + path
  else
    'svn://mark.heily.com/' + path
  end
end

# Return an authenticated or anonymous SVN URI for SourceForge
def sf_svn(path,branch)
  if ENV['USER'] == 'mheily'
    "svn+ssh://mheily@svn.code.sf.net/p/#{path}/code/#{branch}"
  else
    "svn://svn.code.sf.net/p/#{path}/code/#{branch}"
  end
end

# Return a libdispatch Test object
def dispatch_test(id, src)
    extra_cflags = ''

    extra_cflags = '-D_GNU_SOURCE'      # for glibc

  # Workaround for different build path on Android
  if SystemType.host =~ /-androideabi$/
    # FIXME: should include libkqueue & libpwq
    ldadd = 'libdispatch-197/obj/local/armeabi-v7a/libdispatch.a'

    # Workaround for error compiling <TargetConditional.h>
    extra_cflags += ' -DTARGET_CPU_ARM=1 -DTARGET_OS_EMBEDDED'
  else
    ldadd = ['libdispatch.a',
             'libBlocksRuntime/libBlocksRuntime.a',
             'libkqueue/libkqueue.a',
             'libpthread_workqueue/libpthread_workqueue.a',
             '-lpthread', 
             '-lrt']
             ldadd = ['-ldispatch', '-lpthread', '-lrt' ]
  end

  Test.new(
    :id => id,
    :cflags => '-fblocks -Ilibdispatch-197 -Ilibdispatch-197/include -IlibBlocksRuntime -Ilibpthread_workqueue/include ' + extra_cflags,
    :sources => [ src, 'dispatch_test.c' ].map { |p| 'libdispatch-197/testing/' + p },
    :ldadd => ldadd
    )
end

cc = CCompiler.new(
  :search => %w{clang gcc cc}
)

project = Project.new(
  :id => 'opengcd',
  :version => '0.2',
  :config_h => 'libdispatch-197/config/config.h',
  :cc => cc
)
project.custom_configure_script = true

# Require the use of the Clang toolchain for Android.
if SystemType.host =~ /-androideabi$/
  project.ndk_toolchain_version = 'clang3.2'
end

project.add(
  ExternalProject.new(
       :id => 'libBlocksRuntime',
       :uri => sf_svn('blocksruntime', 'trunk'),
       :configure => './configure.rb'
      ),
  ExternalProject.new(
       :id => 'libkqueue',
       :uri => sf_svn('libkqueue', 'trunk'),
       :configure => './configure.rb'
      ),
  ExternalProject.new(
       :id => 'libpthread_workqueue',
       :uri => sf_svn('libpwq', 'trunk'),
       :configure => './configure.rb'
      ),

  # Update all dependencies and force everything to be rebuilt
  #(TODO -- move into makeconf)
  Target.new('update', [], [
      'svn up',
      'cd libBlocksRuntime && svn up && rm -rf obj',
      'cd libkqueue && svn up && rm -rf obj',
      'cd libpthread_workqueue && svn up && rm -rf obj',
      'rm -rf obj',
      'rm -f *-stamp'
      ]),

#DEADWOOD---
  Target.new('libdispatchOLD', [], [
      # Use the same steps as the Debian build process
      'tar zxf libdispatch_0\~svn197.orig.tar.gz',
      'patch -p0 < patch/disable_dispatch_read.patch',
      'patch -p0 < patch/libdispatch-r197_v2.patch',
      'mv libdispatch-0~svn197 libdispatch',


      # Extra stuff for Android
      'cd libdispatch && patch -p0 < ../patch/dispatch-workaround.diff',
      'cd libdispatch && patch -p0 < ../patch/dispatch-spawn.diff',
      'cd libdispatch && patch -p0 < ../patch/dispatch-atomic.diff',
      'cd libdispatch && patch -p0 < ../patch/dispatch-semaphore.diff',
      'cd libdispatch && patch -p0 < ../patch/dispatch-blocks.diff',
      'cd libdispatch && patch -p0 < ../patch/dispatch-internal.diff',

     'cd libdispatch && CC=$(CC)' +
       ' PKG_CONFIG_PATH=../libkqueue' +
       ' CFLAGS="-nostdlib -I../libkqueue/include -I../libpthread_workqueue/include -I../libBlocksRuntime"' +
       ' LIBS="-lBlocksRuntime"' +
       ' LDFLAGS="-Wl,-rpath-link=$(NDK_LIBDIR) -L$(NDK_LIBDIR) -L../libBlocksRuntime/obj/local/armeabi-v7a"' +
       ' ./configure --host=arm-linux-androideabi'
      ]),


  Header.new(
      :id => 'libdispatch',
      :namespace => 'dispatch',
      :sources => 'libdispatch/dispatch/*.h'
  ),

  Header.new(
      :id => 'libBlocksRuntime',
      :sources => 'libBlocksRuntime/Block.h'
  ),

  Library.new(
      :id => 'libdispatch',
      :cflags => '-fblocks -D_GNU_SOURCE -D__BLOCKS__ -I./libdispatch-197 -I./libdispatch-197/src -I./libkqueue/include -I./libpthread_workqueue/include -I./libBlocksRuntime',
      :ldadd => [
                 'libBlocksRuntime/libBlocksRuntime.a',
                 'libkqueue/libkqueue.a',
                 'libpthread_workqueue/libpthread_workqueue.a'],
      :sources => %w{ 
         ../../libBlocksRuntime/data.c
         apply.c
         benchmark.c
         object.c
         once.c
         queue.c
         queue_kevent.c
         semaphore.c
         source.c
         source_kevent.c
         time.c
         shims/mach.c
         shims/time.c
         shims/tsd.c
      }.map { |p| 'libdispatch-197/src/' + p }
  ),
  dispatch_test('dispatch-api', 'dispatch_api.c'),
  dispatch_test('dispatch-c99', 'dispatch_c99.c'),
  dispatch_test('dispatch-cascade', 'dispatch_cascade.c'),
  dispatch_test('dispatch-debug', 'dispatch_debug.c'),
  dispatch_test('dispatch-priority', 'dispatch_priority.c'),
#FIXME:dispatch_test('dispatch-priority2', 'dispatch_priority.c'),
  dispatch_test('dispatch-starfish', 'dispatch_starfish.c'),
  dispatch_test('dispatch-after', 'dispatch_after.c'),
  dispatch_test('dispatch-apply', 'dispatch_apply.c'),
  dispatch_test('dispatch-drift', 'dispatch_drift.c'),
  dispatch_test('dispatch-group', 'dispatch_group.c'),
  dispatch_test('dispatch-pingpong', 'dispatch_pingpong.c'),
#FIXME: broken on Linux w old libkqueue
#  dispatch_test('dispatch-read', 'dispatch_read.c'),
  dispatch_test('dispatch-readsync', 'dispatch_readsync.c'),
  dispatch_test('dispatch-sema', 'dispatch_sema.c'),
  dispatch_test('dispatch-timer_bit31', 'dispatch_timer_bit31.c'),
  dispatch_test('dispatch-timer_bit63', 'dispatch_timer_bit63.c')
)

if SystemType.host =~ /-androideabi$/

  project.add Target.new('binary-release', [], [
     "tar --transform 's/^/libdispatch-0.1-arm-linux-androideabi/' --exclude='Makefile' --exclude 'Makefile.am' -zcvf libdispatch-0.1-arm-linux-androideabi.tgz libdispatch.a libdispatch.so libdispatch/dispatch libBlocksRuntime/Block.h"
  ])

####project.add ExternalProject.new(
  ##     :id => 'libdispatch',
  ##     :uri => 'file://libdispatch.tgz',
  ##     :buildable => false,
  ##     :patch => %w{ 
  ##                    disable_dispatch_read.patch
  ##                    libdispatch-r197_v2.patch
  ##                    dispatch-workaround.diff
  ##                    dispatch-spawn.diff
  ##                    dispatch-atomic.diff
  ##                    dispatch-semaphore.diff
  ##                    dispatch-blocks.diff
  ##                    dispatch-internal.diff
  ##                  }.map { |path| 'patch/' + path },
  ##   :configure => 'CC=' + project.cc.path +
  ##     ' CFLAGS="--sysroot=' + project.cc.sysroot + ' -I../libkqueue/include -I../libpthread_workqueue/include -I../libBlocksRuntime"' +
  ##     ' LIBS=""' +
  ##     ' LDFLAGS="-Wl,-rpath-link=' + project.ndk_libdir + ' -L' + project.ndk_libdir + ' -L../libBlocksRuntime/obj/local/armeabi-v7a"' +
  ##     ' ./configure'
  ##    )

else
  # Assume it is Linux for now..
####project.add ExternalProject.new(
  ##     :id => 'libdispatch',
  ##     :uri => 'file://libdispatch.tgz',
  ##     :patch => %w{ 
  ##                    dispatch-private_extern.diff
  ##                 }.map { |path| 'patch/' + path },
  ##     :buildable => false,
  ##     :configure => 
  ##     
  ##     # FIXME: this needs to be expressed as a formal build dependency
  ##     'cd ../libBlocksRuntime && make && cd ../libdispatch && ' +

  ##     'CC=' + project.cc.path +
  ##     ' CFLAGS="-I../libkqueue/include -I../libpthread_workqueue/include -I../libBlocksRuntime"' +
  ##     ' LIBS=""' +
  ##     ' LDFLAGS="-L../libBlocksRuntime"' +
  ##     ' ./configure'
  ##    )
end

project.check_function 'clock_gettime', :ldadd => '-lrt'
project.check_function 'pthread_create', :include => 'pthread.h', :ldadd => '-lpthread' 
project.check_header %w{ TargetConditionals.h pthread_machdep.h pthread_np.h malloc/malloc.h libkern/OSCrossEndian.h libkern/OSAtomic.h sys/sysctl.h }
project.check_header %w{ CoreServices/CoreServices.h }
project.check_header %w{ mach/mach.h }
#if project.check_header %w{ pthread_workqueue.h }
  project.define 'HAVE_PTHREAD_WORKQUEUES'
#end
project.check_decl %w{ CLOCK_UPTIME CLOCK_MONOTONIC CLOCK_REALTIME}, 
    :include => 'time.h'
project.check_decl %w{ EVFILT_LIO EVFILT_SESSION NOTE_NONE NOTE_REAP NOTE_REVOKE NOTE_SIGNAL },
    :include => ['sys/types.h', 'sys/event.h' ]
project.check_decl 'FD_COPY', :include => 'sys/select.h'
project.check_decl 'SIGEMT', :include => 'signal.h'
project.check_decl %w{VQ_UPDATE VQ_VERYLOWDISK}, :include => 'sys/mount.h'
project.check_decl 'program_invocation_short_name', :include => 'errno.h', :cflags => '-D_GNU_SOURCE'
project.check_function %w{ pthread_key_init_np pthread_main_np mach_absolute_time malloc_create_zone sysconf getprogname getexecname vasprintf asprintf arc4random fgetln }, :include => 'unistd.h'
project.check_decl 'POSIX_SPAWN_START_SUSPENDED', :include => 'sys/spawn.h'
if project.check_function 'sem_init', :include => 'semaphore.h', :ldadd => '-lpthread'
  project.define 'USE_POSIX_SEM'
end
project.check_header 'sys/cdefs.h'
project.check_header 'unistd.h'
project.define 'DISPATCH_NO_LEGACY'
project.define 'USE_LIBDISPATCH_INIT_CONSTRUCTOR'


##### libdispatch-197 stuff
##### end libdispatch-197 stuff
mc = Makeconf.new
mc.configure(project)
