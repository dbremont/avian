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
make
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

  * Linux (i386, x86_64, ARM, and ARM64)


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


Embedding
---------

The following series of commands illustrates how to produce a
stand-alone executable out of a Java application using Avian.

Note: if you are building on Cygwin, prepend "x86_64-w64-mingw32-" or
"i686-w64-mingw32-" to the ar, g++, gcc, strip, and dlltool commands
below (e.g. x86_64-w64-mingw32-gcc).

__1.__ Build Avian, create a new directory, and populate it with the
VM object files and bootstrap classpath jar.

    $ make
    $ mkdir hello
    $ cd hello
    $ ar x ../build/${platform}-${arch}/libavian.a
    $ cp ../build/${platform}-${arch}/classpath.jar boot.jar

__2.__ Build the Java code and add it to the jar.

    $ cat >Hello.java <<EOF
    public class Hello {
      public static void main(String[] args) {
        System.out.println("hello, world!");
      }
    }
    EOF
     $ javac -bootclasspath boot.jar Hello.java
     $ jar u0f boot.jar Hello.class

__3.__ Make an object file out of the jar.

    $ ../build/${platform}-${arch}/binaryToObject/binaryToObject boot.jar \
         boot-jar.o _binary_boot_jar_start _binary_boot_jar_end ${platform} ${arch}

If you've built Avian using the `lzma` option, you may optionally
compress the jar before generating the object:

      ../build/$(platform}-${arch}-lzma/lzma/lzma encode boot.jar boot.jar.lzma
         && ../build/${platform}-${arch}-lzma/binaryToObject/binaryToObject \
           boot.jar.lzma boot-jar.o _binary_boot_jar_start _binary_boot_jar_end \
           ${platform} ${arch}

Note that you'll need to specify "-Xbootclasspath:[lzma.bootJar]"
instead of "-Xbootclasspath:[bootJar]" in the next step if you've used
LZMA to compress the jar.

__4.__ Write a driver which starts the VM and runs the desired main
method.  Note the bootJar function, which will be called by the VM to
get a handle to the embedded jar.  We tell the VM about this jar by
setting the boot classpath to "[bootJar]".

    $ cat >embedded-jar-main.cpp <<EOF
    #include "stdint.h"
    #include "jni.h"
    #include "stdlib.h"

    #if (defined __MINGW32__) || (defined _MSC_VER)
    #  define EXPORT __declspec(dllexport)
    #else
    #  define EXPORT __attribute__ ((visibility("default"))) \
      __attribute__ ((used))
    #endif

    #if (! defined __x86_64__) && ((defined __MINGW32__) || (defined _MSC_VER))
    #  define SYMBOL(x) binary_boot_jar_##x
    #else
    #  define SYMBOL(x) _binary_boot_jar_##x
    #endif

    extern "C" {

      extern const uint8_t SYMBOL(start)[];
      extern const uint8_t SYMBOL(end)[];

      EXPORT const uint8_t*
      bootJar(size_t* size)
      {
        *size = SYMBOL(end) - SYMBOL(start);
        return SYMBOL(start);
      }

    } // extern "C"

    extern "C" void __cxa_pure_virtual(void) { abort(); }

    int
    main(int ac, const char** av)
    {
      JavaVMInitArgs vmArgs;
      vmArgs.version = JNI_VERSION_1_2;
      vmArgs.nOptions = 1;
      vmArgs.ignoreUnrecognized = JNI_TRUE;

      JavaVMOption options[vmArgs.nOptions];
      vmArgs.options = options;

      options[0].optionString = const_cast<char*>("-Xbootclasspath:[bootJar]");

      JavaVM* vm;
      void* env;
      JNI_CreateJavaVM(&vm, &env, &vmArgs);
      JNIEnv* e = static_cast<JNIEnv*>(env);

      jclass c = e->FindClass("Hello");
      if (not e->ExceptionCheck()) {
        jmethodID m = e->GetStaticMethodID(c, "main", "([Ljava/lang/String;)V");
        if (not e->ExceptionCheck()) {
          jclass stringClass = e->FindClass("java/lang/String");
          if (not e->ExceptionCheck()) {
            jobjectArray a = e->NewObjectArray(ac-1, stringClass, 0);
            if (not e->ExceptionCheck()) {
              for (int i = 1; i < ac; ++i) {
                e->SetObjectArrayElement(a, i-1, e->NewStringUTF(av[i]));
              }

              e->CallStaticVoidMethod(c, m, a);
            }
          }
        }
      }

      int exitCode = 0;
      if (e->ExceptionCheck()) {
        exitCode = -1;
        e->ExceptionDescribe();
      }

      vm->DestroyJavaVM();

      return exitCode;
    }
    EOF

__on Linux:__

     $ g++ -I$JAVA_HOME/include -I$JAVA_HOME/include/linux \
         -D_JNI_IMPLEMENTATION_ -c embedded-jar-main.cpp -o main.o

__on Mac OS X:__

     $ g++ -I$JAVA_HOME/include -I$JAVA_HOME/include/darwin \
         -D_JNI_IMPLEMENTATION_ -c embedded-jar-main.cpp -o main.o

__on Windows:__

     $ g++ -fno-exceptions -fno-rtti -I"$JAVA_HOME/include" -I"$JAVA_HOME/include/win32" \
         -D_JNI_IMPLEMENTATION_ -c embedded-jar-main.cpp -o main.o

__5.__ Link the objects produced above to produce the final
executable, and optionally strip its symbols.

__on Linux:__

    $ g++ -rdynamic *.o -ldl -lpthread -lz -o hello
    $ strip --strip-all hello

Embedding with ProGuard and a Boot Image
----------------------------------------

The following illustrates how to embed an application as above, except
this time we preprocess the code using ProGuard and build a boot image
from it for quicker startup.  The pros and cons of using ProGuard are
as follow:

 * Pros: ProGuard will eliminate unused code, optimize the rest, and
   obfuscate it as well for maximum space savings

 * Cons: increased build time, especially for large applications, and
   extra effort needed to configure it for applications which rely
   heavily on reflection and/or calls to Java from native code

For boot image builds:

 * Pros: the boot image build pre-parses all the classes and compiles
   all the methods, obviating the need for JIT compilation at runtime.
   This also makes garbage collection faster, since the pre-parsed
   classes are never visited.

 * Cons: the pre-parsed classes and AOT-compiled methods take up more
   space in the executable than the equivalent class files.  In
   practice, this can make the executable 30-50% larger.  Also, AOT
   compilation does not yet yield significantly faster or smaller code
   than JIT compilation.  Finally, floating point code may be slower
   on 32-bit x86 since the compiler cannot assume SSE2 support will be
   available at runtime, and the x87 FPU is not supported except via
   out-of-line helper functions.

Note you can use ProGuard without using a boot image and vice-versa,
as desired.

The following instructions assume we are building for Linux/x86_64.
Please refer to the previous example for guidance on other platforms.

__1.__ Build Avian, create a new directory, and populate it with the
VM object files.

    $ make bootimage=true
    $ mkdir hello
    $ cd hello
    $ ar x ../build/linux-x86_64-bootimage/libavian.a

__2.__ Create a stage1 directory and extract the contents of the
class library jar into it.

    $ mkdir stage1
    $ (cd stage1 && jar xf ../../build/linux-x86_64-bootimage/classpath.jar)

__3.__ Build the Java code and add it to stage1.

     $ cat >Hello.java <<EOF
    public class Hello {
      public static void main(String[] args) {
        System.out.println("hello, world!");
      }
    }
    EOF
     $ javac -bootclasspath stage1 -d stage1 Hello.java

__4.__ Create a ProGuard configuration file specifying Hello.main as
the entry point.

     $ cat >hello.pro <<EOF
    -keep class Hello {
       public static void main(java.lang.String[]);
     }
    EOF

__5.__ Run ProGuard with stage1 as input and stage2 as output.

     $ java -jar ../../proguard4.6/lib/proguard.jar \
         -dontusemixedcaseclassnames -injars stage1 -outjars stage2 \
         @../vm.pro @hello.pro

(note: The -dontusemixedcaseclassnames option is only needed when
building on systems with case-insensitive filesystems such as Windows
and OS X.  Also, you'll need to add -ignorewarnings if you use the
OpenJDK class library since the openjdk-src build does not include all
the JARs from OpenJDK, and thus ProGuard will not be able to resolve
all referenced classes.  If you actually plan to use such classes at
runtime, you'll need to add them to stage1 before running ProGuard.
Finally, you'll need to add @../openjdk.pro to the above command when
using the OpenJDK library.)

__6.__ Build the boot and code images.

     $ ../build/linux-x86_64-bootimage/bootimage-generator \
        -cp stage2 \
        -bootimage bootimage-bin.o \
        -codeimage codeimage-bin.o \
        -hostvm ../build/linux-x86_64-interpret/libjvm.so

Note that you can override the default names for the start and end
symbols in the boot/code image by also passing:

    -bootimage-symbols my_bootimage_start:my_bootimage_end \
    -codeimage-symbols my_codeimage_start:my_codeimage_end

__7.__ Write a driver which starts the VM and runs the desired main
method.  Note the bootimageBin function, which will be called by the
VM to get a handle to the embedded boot image.  We tell the VM about
this function via the "avian.bootimage" property.

Note also that this example includes no resources besides class files.
If our application loaded resources such as images and properties
files via the classloader, we would also need to embed the jar file
containing them.  See the previous example for instructions.

    $ cat >bootimage-main.cpp <<EOF
    #include "stdint.h"
    #include "jni.h"

    #if (defined __MINGW32__) || (defined _MSC_VER)
    #  define EXPORT __declspec(dllexport)
    #else
    #  define EXPORT __attribute__ ((visibility("default")))
    #endif

    #if (! defined __x86_64__) && ((defined __MINGW32__) || (defined _MSC_VER))
    #  define BOOTIMAGE_BIN(x) binary_bootimage_bin_##x
    #  define CODEIMAGE_BIN(x) binary_codeimage_bin_##x
    #else
    #  define BOOTIMAGE_BIN(x) _binary_bootimage_bin_##x
    #  define CODEIMAGE_BIN(x) _binary_codeimage_bin_##x
    #endif

    extern "C" {

      extern const uint8_t BOOTIMAGE_BIN(start)[];
      extern const uint8_t BOOTIMAGE_BIN(end)[];

      EXPORT const uint8_t*
      bootimageBin(size_t* size)
      {
        *size = BOOTIMAGE_BIN(end) - BOOTIMAGE_BIN(start);
        return BOOTIMAGE_BIN(start);
      }

      extern const uint8_t CODEIMAGE_BIN(start)[];
      extern const uint8_t CODEIMAGE_BIN(end)[];

      EXPORT const uint8_t*
      codeimageBin(size_t* size)
      {
        *size = CODEIMAGE_BIN(end) - CODEIMAGE_BIN(start);
        return CODEIMAGE_BIN(start);
      }

    } // extern "C"

    int
    main(int ac, const char** av)
    {
      JavaVMInitArgs vmArgs;
      vmArgs.version = JNI_VERSION_1_2;
      vmArgs.nOptions = 2;
      vmArgs.ignoreUnrecognized = JNI_TRUE;

      JavaVMOption options[vmArgs.nOptions];
      vmArgs.options = options;

      options[0].optionString
        = const_cast<char*>("-Davian.bootimage=bootimageBin");

      options[1].optionString
        = const_cast<char*>("-Davian.codeimage=codeimageBin");

      JavaVM* vm;
      void* env;
      JNI_CreateJavaVM(&vm, &env, &vmArgs);
      JNIEnv* e = static_cast<JNIEnv*>(env);

      jclass c = e->FindClass("Hello");
      if (not e->ExceptionCheck()) {
        jmethodID m = e->GetStaticMethodID(c, "main", "([Ljava/lang/String;)V");
        if (not e->ExceptionCheck()) {
          jclass stringClass = e->FindClass("java/lang/String");
          if (not e->ExceptionCheck()) {
            jobjectArray a = e->NewObjectArray(ac-1, stringClass, 0);
            if (not e->ExceptionCheck()) {
              for (int i = 1; i < ac; ++i) {
                e->SetObjectArrayElement(a, i-1, e->NewStringUTF(av[i]));
              }

              e->CallStaticVoidMethod(c, m, a);
            }
          }
        }
      }

      int exitCode = 0;
      if (e->ExceptionCheck()) {
        exitCode = -1;
        e->ExceptionDescribe();
      }

      vm->DestroyJavaVM();

      return exitCode;
    }
    EOF

     $ g++ -I$JAVA_HOME/include -I$JAVA_HOME/include/linux \
         -D_JNI_IMPLEMENTATION_ -c bootimage-main.cpp -o main.o

__8.__ Link the objects produced above to produce the final
 executable, and optionally strip its symbols.

    $ g++ -rdynamic *.o -ldl -lpthread -lz -o hello
    $ strip --strip-all hello

TBD
----------
1. Remove Windows, MacOS, FreeBSD dependencies.
2. Remove travis ci files
3. Remove android dependency
4. Change the implementation to C

Trademarks
----------

Oracle and Java are registered trademarks of Oracle and/or its
affiliates.  Other names may be trademarks of their respective owners.

The Avian project is not affiliated with Oracle.
