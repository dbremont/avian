Avian - A lightweight Java Virtual Machine (JVM)
================================================


Quick Start
-----------

These are examples of building Avian on various operating systems for
the x86_64 architecture.  You may need to modify JAVA_HOME according
to where the JDK is installed on your system.  In all cases, be sure
to use forward slashes in the path.

## Build

```bash
sdk use java 7.0.352-zulu
make platform=linux arch=x86_64 mode=debug
```

Test:
`build/linux-x86_64-debug/avian -cp  build/linux-x86_64-debug/test Hello`

Introduction
------------

Avian is a lightweight virtual machine and class library designed to
provide a useful subset of Java's features, suitable for building
self-contained applications.


Supported Platforms
-------------------

Avian can currently target the following platforms:

  * Linux (x86_64)


Building
--------

Build requirements include:

  * GNU make 3.80 or later
  * GCC 4.6 or later
      or LLVM Clang 3.1 or later (see use-clang option below)
  * JDK 1.6 or later
  * zlib 1.2.3 or later

Earlier versions of some of these packages may also work but have not
been tested.

The build is directed by a single makefile and may be influenced via
certain flags described below, all of which are optional.

    $ make \
        platform={linux,windows,macosx,ios,freebsd} \
        arch={i386,x86_64,arm,arm64} \
        process={compile,interpret} \
        mode={debug,debug-fast,fast,small} \
        lzma=<lzma source directory> \
        tails={true,false} \
        continuations={true,false} \
        use-clang={true,false} \
        openjdk=<openjdk installation directory> \
        openjdk-src=<openjdk source directory>

  * `platform` - the target platform
    * _default:_ output of $(uname -s | tr [:upper:] [:lower:]),
normalized in some cases (e.g. CYGWIN_NT-5.1 -> windows)

  * `arch` - the target architecture
    * _default:_ output of $(uname -m), normalized in some cases
(e.g. i686 -> i386)

  * `process` - choice between pure interpreter or JIT compiler
    * _default:_ compile

  * `mode` - which set of compilation flags to use to determine
optimization level, debug symbols, and whether to enable
assertions
    * _default:_ fast

  * `lzma` - if set, support use of LZMA to compress embedded JARs and
boot images.  The value of this option should be a directory
containing a recent LZMA SDK (available [here](http://www.7-zip.org/sdk.html)).  Currently, only version 9.20 of
the SDK has been tested, but other versions might work.
    * _default:_ not set


  * `tails` - if true, optimize each tail call by replacing the caller's
stack frame with the callee's.  This convention ensures proper
tail recursion, suitable for languages such as Scheme.  This
option is only valid for process=compile builds.
    * _default:_ false

  * `continuations` - if true, support continuations via the
avian.Continuations methods callWithCurrentContinuation and
dynamicWind.  See Continuations.java for details.  This option is
only valid for process=compile builds.
    * _default:_ false

  * `use-clang` - if true, use LLVM's clang instead of GCC to build.
Note that this does not currently affect cross compiles, only
native builds.
    * _default:_ false

  * `openjdk` - if set, use the OpenJDK class library instead of the
default Avian class library.  See "Building with the OpenJDK Class
Library" below for details.
    * _default:_ not set

  * `openjdk-src` - if this and the openjdk option above are both set,
build an embeddable VM using the OpenJDK class library.  The JNI
components of the OpenJDK class library will be built from the
sources found under the specified directory.  See "Building with
the OpenJDK Class Library" below for details.
    * _default:_ not set


Trademarks
----------

Oracle and Java are registered trademarks of Oracle and/or its
affiliates.  Other names may be trademarks of their respective owners.

The Avian project is not affiliated with Oracle.