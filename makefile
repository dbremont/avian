MAKEFLAGS = -s

name = avian
version := $(shell grep version gradle.properties | cut -d'=' -f2)

get-java-version = $(shell "$1" -version 2>&1 \
		| grep -E 'version "1|version "9' \
		| sed -e 's/.*version "1.\([^.]*\).*/\1/' \
					-e 's/.*version "9.*/9/')

java-version := $(call get-java-version,$(JAVA_HOME)/bin/java)

build-arch := $(shell uname -m \
	| sed 's/^i.86$$/i386/' \
	| sed 's/^x86pc$$/i386/' \
	| sed 's/amd64/x86_64/' \
	| sed 's/^arm.*$$/arm/' \
	| sed 's/aarch64/arm64/')

build-platform := \
	$(shell uname -s | tr [:upper:] [:lower:] \
		| sed \
			-e 's/^mingw64.*$$/mingw32/' \
			-e 's/^mingw32.*$$/mingw32/' \
			-e 's/^cygwin.*$$/cygwin/' \
			-e 's/^darwin.*$$/macosx/')

arch = $(build-arch)
target-arch = $(arch)

platform = $(build-platform)

codegen-targets = native

mode = fast
process = compile

ifneq ($(process),compile)
	options := -$(process)
endif
ifneq ($(mode),fast)
	options := $(options)-$(mode)
endif
ifneq ($(lzma),)
	options := $(options)-lzma
endif

ifeq ($(tails),true)
	options := $(options)-tails
endif
ifeq ($(continuations),true)
	options := $(options)-continuations
endif
ifeq ($(codegen-targets),all)
	options := $(options)-all
endif

ifeq ($(filter debug debug-fast fast stress stress-major small,$(mode)),)
	x := $(error "'$(mode)' is not a valid mode (choose one of: debug debug-fast fast stress stress-major small)")
endif

ifeq ($(filter compile interpret,$(process)),)
	x := $(error "'$(process)' is not a valid process (choose one of: compile interpret)")
endif

ifeq ($(filter x86_64,$(arch)),)
	x := $(error "'$(arch)' is not a supported architecture (choose one of: x86_64)")
endif

ifeq ($(filter linux,$(platform)),)
	x := $(error "'$(platform)' is not a supported platform (choose one of: linux)")
endif

aot-only = false
root := $(shell (cd .. && pwd))
build = build/$(platform)-$(arch)$(options)
host-build-root = $(build)/host
classpath-build = $(build)/classpath
test-build = $(build)/test
src = src
classpath-src = classpath
test = test
unittest = unittest


classpath = avian

ifeq ($(use-werror),true)
	werror = -Werror
endif

test-executable = $(shell pwd)/$(executable)
boot-classpath = $(classpath-build)
embed-prefix = /avian-embedded

native-path = echo

windows-path = echo

path-separator = ;


target-path-separator = :

library-path-variable = LD_LIBRARY_PATH
library-path = $(library-path-variable)=$(build)


ifneq ($(openjdk),)
	openjdk-version := $(call get-java-version,$(openjdk)/bin/java)

	openjdk-arch = $(arch)
	ifeq ($(arch),x86_64)
		openjdk-arch = amd64
	endif

	ifneq ($(openjdk-src),)
		include openjdk-src.mk
		options := $(options)-openjdk-src
		classpath-objects = $(openjdk-objects) $(openjdk-local-objects)
		classpath-cflags = -DAVIAN_OPENJDK_SRC -DBOOT_JAVAHOME
		openjdk-jar-dep = $(build)/openjdk-jar.dep
		classpath-jar-dep = $(openjdk-jar-dep)
		javahome = $(embed-prefix)/javahomeJar
		javahome-files = lib/currency.data lib/security/java.security \
			lib/security/java.policy lib/security/cacerts

		ifneq (,$(wildcard $(openjdk)/jre/lib/zi))
			javahome-files += lib/zi
		endif

		ifneq (,$(wildcard $(openjdk)/jre/lib/tzdb.dat))
			javahome-files += lib/tzdb.dat
		endif

		local-policy = lib/security/local_policy.jar
		ifneq (,$(wildcard $(openjdk)/jre/$(local-policy)))
			javahome-files += $(local-policy)
		endif

		export-policy = lib/security/US_export_policy.jar
		ifneq (,$(wildcard $(openjdk)/jre/$(export-policy)))
			javahome-files += $(export-policy)
		endif

		javahome-object = $(build)/javahome-jar.o
		boot-javahome-object = $(build)/boot-javahome.o
		stub-sources = $(src)/openjdk/stubs.cpp
		stub-objects = $(call cpp-objects,$(stub-sources),$(src),$(build))
	else
		soname-flag = -Wl,-soname -Wl,$(so-prefix)jvm$(so-suffix)
		version-script-flag = -Wl,--version-script=openjdk.ld
		options := $(options)-openjdk
		test-executable = $(shell pwd)/$(executable-dynamic)

		library-path = \
				$(library-path-variable)=$(build):$(openjdk)/jre/lib/$(openjdk-arch)
		
		javahome = "$$($(native-path) "$(openjdk)/jre")"
	endif

	classpath = openjdk
	boot-classpath := "$(boot-classpath)$(path-separator)$$($(native-path) "$(openjdk)/jre/lib/rt.jar")"
	build-javahome = $(openjdk)/jre
endif

ifeq ($(classpath),avian)
	jni-sources := $(shell find $(classpath-src) -name '*.cpp')
	jni-objects = $(call cpp-objects,$(jni-sources),$(classpath-src),$(build))
	classpath-objects = $(jni-objects)
endif

input = List

ifeq ($(use-clang),true)
	build-cxx = clang++ -std=c++11
	build-cc = clang
else
	build-cxx = g++
	build-cc = gcc
endif

mflag = -m64

target-format = elf

cxx = $(build-cxx) $(mflag)
cc = $(build-cc) $(mflag)

ar = ar
ranlib = ranlib
dlltool = dlltool
vg = nice valgrind --num-callers=32 --db-attach=yes --freelist-vol=100000000
vg += --leak-check=full --suppressions=valgrind.supp
db = gdb --args
javac = "$(JAVA_HOME)/bin/javac" -encoding UTF-8
javah = "$(JAVA_HOME)/bin/javah"
jar = "$(JAVA_HOME)/bin/jar"
strip = strip
strip-all = --strip-all

rdynamic = -rdynamic

cflags_debug = -O0 -g3
cflags_debug_fast = -O0 -g3
cflags_stress = -O0 -g3
cflags_stress_major = -O0 -g3
ifeq ($(use-clang),true)
	cflags_fast = -O3 -g3
	cflags_small = -Oz -g3
else
	cflags_fast = -O3 -g3
	cflags_small = -Os -g3
endif

# note that we suppress the non-virtual-dtor warning because we never
# use the delete operator, which means we don't need virtual
# destructors:
warnings = -Wall -Wextra $(werror) -Wunused-parameter -Winit-self \
	-Wno-non-virtual-dtor

target-cflags = -DTARGET_BYTES_PER_WORD=$(pointer-size)

common-cflags = $(warnings) -std=c++0x -fno-rtti -fno-exceptions -I$(classpath-src) \
	"-I$(JAVA_HOME)/include" -I$(src) -I$(build) -Iinclude $(classpath-cflags) \
	-D__STDC_LIMIT_MACROS -D_JNI_IMPLEMENTATION_ -DAVIAN_VERSION=\"$(version)\" \
	-DAVIAN_INFO="\"$(info)\"" \
	-DUSE_ATOMIC_OPERATIONS -DAVIAN_JAVA_HOME=\"$(javahome)\" \
	-DAVIAN_EMBED_PREFIX=\"$(embed-prefix)\" $(target-cflags)

asmflags = $(target-cflags) -I$(src)

ifneq (,$(filter x86_64,$(arch)))
	ifeq ($(use-frame-pointer),true)
		common-cflags += -fno-omit-frame-pointer -DAVIAN_USE_FRAME_POINTER
		asmflags += -DAVIAN_USE_FRAME_POINTER
	endif
endif

build-cflags = $(common-cflags) -fPIC -fvisibility=hidden \
	"-I$(JAVA_HOME)/include/linux" -I$(src) -pthread

converter-cflags = -D__STDC_CONSTANT_MACROS -std=c++0x -Iinclude/ -Isrc/ \
	-fno-rtti -fno-exceptions \
	-DAVIAN_TARGET_ARCH=AVIAN_ARCH_UNKNOWN \
	-DAVIAN_TARGET_FORMAT=AVIAN_FORMAT_UNKNOWN \
	-Wall -Wextra $(werror) -Wunused-parameter -Winit-self -Wno-non-virtual-dtor

cflags = $(build-cflags)

common-lflags = -lm -lz

ifeq ($(use-clang),true)
	common-lflags += -Wl,-E
endif

build-lflags = -lz -lpthread -ldl

lflags = $(common-lflags) -lpthread -ldl

build-system = posix

system = posix
asm = x86

pointer-size = 8

so-prefix = lib
so-suffix = .so

static-prefix = lib
static-suffix = .a

output = -o $(1)
asm-output = -o $(1)
asm-input = -c $(1)
asm-format = S
as = $(cc)
ld = $(cc)
build-ld = $(build-cc)
build-ld-cpp = $(build-cxx)

default-remote-test-host = localhost
default-remote-test-port = 22
ifeq ($(remote-test-host),)
	remote-test-host = $(default-remote-test-host)
else
	remote-test = true
endif
ifeq ($(remote-test-port),)
	remote-test-port = $(default-remote-test-port)
else
	remote-test = true
endif
remote-test-user = ${USER}
remote-test-dir = /tmp/avian-test-${USER}

static = -static
shared = -shared

rpath = -Wl,-rpath=\$$ORIGIN -Wl,-z,origin

openjdk-extra-cflags = -fvisibility=hidden

codeimage-symbols = _binary_codeimage_bin_start:_binary_codeimage_bin_end


openjdk-extra-cflags += $(classpath-extra-cflags)

find-tool = $(shell if ( command -v "$(1)$(2)" >/dev/null ); then (echo "$(1)$(2)") else (echo "$(2)"); fi)

ifeq ($(mode),debug)
	optimization-cflags = $(cflags_debug)
	converter-cflags += $(cflags_debug)
	strip = :
endif
ifeq ($(mode),debug-fast)
	optimization-cflags = $(cflags_debug_fast) -DNDEBUG
	strip = :
endif
ifeq ($(mode),stress)
	optimization-cflags = $(cflags_stress) -DVM_STRESS
	strip = :
endif
ifeq ($(mode),stress-major)
	optimization-cflags = $(cflags_stress_major) -DVM_STRESS -DVM_STRESS_MAJOR
	strip = :
endif
ifeq ($(mode),fast)
	optimization-cflags = $(cflags_fast) -DNDEBUG
endif
ifeq ($(mode),small)
	optimization-cflags = $(cflags_small) -DNDEBUG
endif

ifeq ($(use-lto),true)
	ifeq ($(use-clang),true)
		optimization-cflags += -flto
		lflags += $(optimization-cflags)
	else
# only try to use LTO when GCC 4.6.0 or greater is available
		gcc-major := $(shell $(cc) -dumpversion | cut -f1 -d.)
		gcc-minor := $(shell $(cc) -dumpversion | cut -f2 -d.)
		ifeq ($(shell expr 4 \< $(gcc-major) \
				\| \( 4 \<= $(gcc-major) \& 6 \<= $(gcc-minor) \)),1)
			optimization-cflags += -flto
			no-lto = -fno-lto
			lflags += $(optimization-cflags)
		endif
	endif
endif

cflags += $(optimization-cflags)

c-objects = $(foreach x,$(1),$(patsubst $(2)/%.c,$(3)/%.o,$(x)))
cpp-objects = $(foreach x,$(1),$(patsubst $(2)/%.cpp,$(3)/%.o,$(x)))
cc-objects = $(foreach x,$(1),$(patsubst $(2)/%.cc,$(3)/%.o,$(x)))
asm-objects = $(foreach x,$(1),$(patsubst $(2)/%.$(asm-format),$(3)/%-asm.o,$(x)))
java-classes = $(foreach x,$(1),$(patsubst $(2)/%.java,$(3)/%.class,$(x)))
noop-files = $(foreach x,$(1),$(patsubst $(2)/%,$(3)/%,$(x)))

generated-code = \
	$(build)/type-enums.cpp \
	$(build)/type-declarations.cpp \
	$(build)/type-constructors.cpp \
	$(build)/type-initializations.cpp \
	$(build)/type-java-initializations.cpp \
	$(build)/type-name-initializations.cpp \
	$(build)/type-maps.cpp

vm-depends := $(generated-code) \
	$(shell find src include -name '*.h' -or -name '*.inc.cpp')

vm-sources = \
	$(src)/system/$(system).cpp \
	$(wildcard $(src)/system/$(system)/*.cpp) \
	$(src)/finder.cpp \
	$(src)/machine.cpp \
	$(src)/util.cpp \
	$(src)/heap/heap.cpp \
	$(src)/$(process).cpp \
	$(src)/classpath-$(classpath).cpp \
	$(src)/builtin.cpp \
	$(src)/jnienv.cpp \
	$(src)/process.cpp \
	$(src)/heapdump.cpp

vm-asm-sources = $(src)/$(arch).$(asm-format)

target-asm = $(asm)

build-embed = $(build)/embed
build-embed-loader = $(build)/embed-loader

embed-loader-sources = $(src)/embedded-loader.cpp
embed-loader-objects = $(call cpp-objects,$(embed-loader-sources),$(src),$(build-embed-loader))

embed-sources = $(src)/embed.cpp
embed-objects = $(call cpp-objects,$(embed-sources),$(src),$(build-embed))

compiler-sources = \
	$(src)/codegen/compiler.cpp \
	$(wildcard $(src)/codegen/compiler/*.cpp) \
	$(src)/debug-util.cpp \
	$(src)/codegen/runtime.cpp \
	$(src)/codegen/targets.cpp \
	$(src)/util/fixed-allocator.cpp

x86-assembler-sources = $(wildcard $(src)/codegen/target/x86/*.cpp)

all-assembler-sources = $(x86-assembler-sources) 

native-assembler-sources = $($(target-asm)-assembler-sources)

all-codegen-target-sources = \
	$(compiler-sources) \
	$(native-assembler-sources)

ifeq ($(process),compile)
	vm-sources += $(compiler-sources)

	ifeq ($(codegen-targets),native)
		vm-sources += $(native-assembler-sources)
	endif
	vm-asm-sources += $(src)/compile-$(arch).$(asm-format)
endif
ifeq ($(aot-only),true)
	cflags += -DAVIAN_AOT_ONLY
endif

vm-cpp-objects = $(call cpp-objects,$(vm-sources),$(src),$(build))
all-codegen-target-objects = $(call cpp-objects,$(all-codegen-target-sources),$(src),$(build))
vm-asm-objects = $(call asm-objects,$(vm-asm-sources),$(src),$(build))
vm-objects = $(vm-cpp-objects) $(vm-asm-objects)

heapwalk-sources = $(src)/heapwalk.cpp
heapwalk-objects = \
	$(call cpp-objects,$(heapwalk-sources),$(src),$(build))

unittest-objects = $(call cpp-objects,$(unittest-sources),$(unittest),$(build)/unittest)

vm-heapwalk-objects = $(heapwalk-objects)

ifeq ($(tails),true)
	cflags += -DAVIAN_TAILS
endif

ifeq ($(continuations),true)
	cflags += -DAVIAN_CONTINUATIONS
	asmflags += -DAVIAN_CONTINUATIONS
endif

ifneq ($(mode),fast)
	host-vm-options := -$(mode)
endif

host-vm = build/$(build-platform)-$(build-arch)-interpret$(host-vm-options)/$(so-prefix)jvm$(so-suffix)


vm-classpath-objects = $(classpath-object)
cflags += -DBOOT_CLASSPATH=\"[classpathJar]\" \
	-DAVIAN_CLASSPATH=\"[classpathJar]\"

cflags += $(extra-cflags)
lflags += $(extra-lflags)

openjdk-cflags += $(extra-cflags)

driver-source = $(src)/main.cpp
driver-object = $(build)/main.o
driver-dynamic-objects = \
	$(build)/main-dynamic.o

boot-source = $(src)/boot.cpp
boot-object = $(build)/boot.o

generator-depends := $(wildcard $(src)/*.h)
generator-sources = \
	$(src)/tools/type-generator/main.cpp \
	$(src)/system/$(build-system).cpp \
	$(wildcard $(src)/system/$(build-system)/*.cpp) \
	$(src)/finder.cpp \
	$(src)/util/arg-parser.cpp

ifneq ($(lzma),)
	common-cflags += -I$(lzma) -DAVIAN_USE_LZMA

	vm-sources += \
		$(src)/lzma-decode.cpp

	generator-sources += \
		$(src)/lzma-decode.cpp

	lzma-decode-sources = \
		$(lzma)/C/LzmaDec.c

	lzma-decode-objects = \
		$(call c-objects,$(lzma-decode-sources),$(lzma)/C,$(build))

	lzma-encode-sources = \
		$(lzma)/C/LzmaEnc.c \
		$(lzma)/C/LzFind.c

	lzma-encode-objects = \
		$(call c-objects,$(lzma-encode-sources),$(lzma)/C,$(build))

	lzma-encoder = $(build)/lzma/lzma

	lzma-build-cflags = -D_7ZIP_ST -D__STDC_CONSTANT_MACROS \
		-fno-exceptions -fPIC -I$(lzma)/C

	lzma-cflags = $(lzma-build-cflags) $(classpath-extra-cflags)

	lzma-encoder-sources = \
		$(src)/lzma/main.cpp

	lzma-encoder-objects = \
		$(call cpp-objects,$(lzma-encoder-sources),$(src),$(build))

	lzma-encoder-lzma-sources = $(lzma-encode-sources) $(lzma-decode-sources)

	lzma-encoder-lzma-objects = \
		$(call generator-c-objects,$(lzma-encoder-lzma-sources),$(lzma)/C,$(build))

	lzma-loader = $(build)/lzma/load.o

	lzma-library = $(build)/libavian-lzma.a
endif

generator-cpp-objects = \
	$(foreach x,$(1),$(patsubst $(2)/%.cpp,$(3)/%-build.o,$(x)))
generator-c-objects = \
	$(foreach x,$(1),$(patsubst $(2)/%.c,$(3)/%-build.o,$(x)))
generator-objects = \
	$(call generator-cpp-objects,$(generator-sources),$(src),$(build))
generator-lzma-objects = \
	$(call generator-c-objects,$(lzma-decode-sources),$(lzma)/C,$(build))
generator = $(build)/generator

all-depends = $(shell find include -name '*.h')

object-writer-depends = $(shell find $(src)/tools/object-writer -name '*.h')
object-writer-sources = $(shell find $(src)/tools/object-writer -name '*.cpp')
object-writer-objects = $(call cpp-objects,$(object-writer-sources),$(src),$(build))

binary-to-object-depends = $(shell find $(src)/tools/binary-to-object/ -name '*.h')
binary-to-object-sources = $(shell find $(src)/tools/binary-to-object/ -name '*.cpp')
binary-to-object-objects = $(call cpp-objects,$(binary-to-object-sources),$(src),$(build))

converter-sources = $(object-writer-sources)

converter-tool-depends = $(binary-to-object-depends) $(all-depends)
converter-tool-sources = $(binary-to-object-sources)

converter-objects = $(call cpp-objects,$(converter-sources),$(src),$(build))
converter-tool-objects = $(call cpp-objects,$(converter-tool-sources),$(src),$(build))
converter = $(build)/binaryToObject/binaryToObject

static-library = $(build)/$(static-prefix)$(name)$(static-suffix)
executable = $(build)/$(name)${exe-suffix}
dynamic-library = $(build)/$(so-prefix)jvm$(so-suffix)
executable-dynamic = $(build)/$(name)-dynamic$(exe-suffix)

unittest-executable = $(build)/$(name)-unittest${exe-suffix}

ifneq ($(classpath),avian)
# Assembler, ConstantPool, and Stream are not technically needed for a
# working build, but we include them since our Subroutine test uses
# them to synthesize a class:
	classpath-sources := \
		$(classpath-src)/avian/Addendum.java \
		$(classpath-src)/avian/AnnotationInvocationHandler.java \
		$(classpath-src)/avian/Assembler.java \
		$(classpath-src)/avian/Callback.java \
		$(classpath-src)/avian/Cell.java \
		$(classpath-src)/avian/ClassAddendum.java \
		$(classpath-src)/avian/Classes.java \
		$(classpath-src)/avian/Code.java \
		$(classpath-src)/avian/ConstantPool.java \
		$(classpath-src)/avian/Continuations.java \
		$(classpath-src)/avian/FieldAddendum.java \
		$(classpath-src)/avian/Function.java \
		$(classpath-src)/avian/IncompatibleContinuationException.java \
		$(classpath-src)/avian/InnerClassReference.java \
		$(classpath-src)/avian/Machine.java \
		$(classpath-src)/avian/MethodAddendum.java \
		$(classpath-src)/avian/Pair.java \
		$(classpath-src)/avian/Singleton.java \
		$(classpath-src)/avian/Stream.java \
		$(classpath-src)/avian/SystemClassLoader.java \
		$(classpath-src)/avian/Traces.java \
		$(classpath-src)/avian/VMClass.java \
		$(classpath-src)/avian/VMField.java \
		$(classpath-src)/avian/VMMethod.java \
		$(classpath-src)/avian/avianvmresource/Handler.java \
		$(classpath-src)/avian/file/Handler.java \
		$(classpath-src)/java/lang/invoke/MethodHandle.java \
		$(classpath-src)/java/lang/invoke/MethodHandles.java \
		$(classpath-src)/java/lang/invoke/MethodType.java \
		$(classpath-src)/java/lang/invoke/LambdaMetafactory.java \
		$(classpath-src)/java/lang/invoke/LambdaConversionException.java \
		$(classpath-src)/java/lang/invoke/CallSite.java

	ifeq ($(openjdk),)
		classpath-sources := $(classpath-sources) \
			$(classpath-src)/dalvik/system/BaseDexClassLoader.java \
			$(classpath-src)/libcore/reflect/AnnotationAccess.java \
			$(classpath-src)/sun/reflect/ConstantPool.java \
			$(classpath-src)/java/net/ProtocolFamily.java \
			$(classpath-src)/java/net/StandardProtocolFamily.java \
			$(classpath-src)/sun/misc/Cleaner.java \
			$(classpath-src)/sun/misc/Unsafe.java \
			$(classpath-src)/java/lang/Object.java \
			$(classpath-src)/java/lang/Class.java \
			$(classpath-src)/java/lang/ClassLoader.java \
			$(classpath-src)/java/lang/Package.java \
			$(classpath-src)/java/lang/reflect/Proxy.java \
			$(classpath-src)/java/lang/reflect/Field.java \
			$(classpath-src)/java/lang/reflect/SignatureParser.java \
			$(classpath-src)/java/lang/reflect/Constructor.java \
			$(classpath-src)/java/lang/reflect/AccessibleObject.java \
			$(classpath-src)/java/lang/reflect/Method.java
	endif
else
	classpath-sources := $(shell find $(classpath-src) -name '*.java')
endif

classpath-classes = \
	$(call java-classes,$(classpath-sources),$(classpath-src),$(classpath-build))
classpath-object = $(build)/classpath-jar.o
classpath-dep = $(classpath-build).dep

vm-classes = \
	avian/*.class \
	avian/resource/*.class

test-support-sources = $(shell find $(test)/avian/ -name '*.java')
test-sources := $(wildcard $(test)/*.java)

# HACK ALERT!!
# This test fails regularly on travis, but nowhere else.  We have yet to spend the time to investigate that test, so we disable it on PR builds.
# Note: travis set TRAVIS_PULL_REQUEST environment variable to either the PR number or "false", as appropriate
ifeq (false,$(TRAVIS_PULL_REQUEST))
else
ifeq (,$(TRAVIS_PULL_REQUEST))
else
	test-sources := $(subst $(test)/Trace.java,,$(test-sources))
endif
endif

ifeq (7,$(java-version))
	test-sources := $(subst $(test)/InvokeDynamic.java,,$(test-sources))
	test-sources := $(subst $(test)/Interfaces.java,,$(test-sources))
endif

test-cpp-sources = $(wildcard $(test)/*.cpp)
test-sources += $(test-support-sources)
test-support-classes = $(call java-classes, $(test-support-sources),$(test),$(test-build))
test-classes = $(call java-classes,$(test-sources),$(test),$(test-build))
test-cpp-objects = $(call cpp-objects,$(test-cpp-sources),$(test),$(test-build))
test-library = $(build)/$(so-prefix)test$(so-suffix)
test-dep = $(test-build).dep

test-extra-sources = $(wildcard $(test)/extra/*.java)
test-extra-classes = \
	$(call java-classes,$(test-extra-sources),$(test),$(test-build))
test-extra-dep = $(test-build)-extra.dep

unittest-sources = \
	$(wildcard $(unittest)/*.cpp) \
	$(wildcard $(unittest)/util/*.cpp) \
	$(wildcard $(unittest)/codegen/*.cpp)

unittest-depends = \
	$(wildcard $(unittest)/*.h)

ifeq ($(continuations),true)
	continuation-tests = \
		extra.ComposableContinuations \
		extra.Continuations \
		extra.Coroutines \
		extra.DynamicWind
endif

ifeq ($(tails),true)
	tail-tests = \
		extra.Tails
endif

ifeq ($(target-arch),x86_64)
	cflags += -DAVIAN_TARGET_ARCH=AVIAN_ARCH_X86_64
endif

ifeq ($(target-format),elf)
	cflags += -DAVIAN_TARGET_FORMAT=AVIAN_FORMAT_ELF
endif

ifeq ($(target-format),pe)
	cflags += -DAVIAN_TARGET_FORMAT=AVIAN_FORMAT_PE
endif

ifeq ($(target-format),macho)
	cflags += -DAVIAN_TARGET_FORMAT=AVIAN_FORMAT_MACHO
endif

class-name = $(patsubst $(1)/%.class,%,$(2))
class-names = $(foreach x,$(2),$(call class-name,$(1),$(x)))

test-flags = -Djava.library.path=$(build) \
	-cp '$(build)/test$(target-path-separator)$(build)/extra-dir'

test-args = $(test-flags) $(input)

ifneq ($(filter linux,$(platform)),)
eclipse-exec-env = eclipse-ee
eclipse-jdk-dir = $(build)/eclipse/jdk
eclipse-ee-file = $(eclipse-jdk-dir)/avian.ee
eclipse-bin-dir = $(eclipse-jdk-dir)/bin
eclipse-lib-dir = $(eclipse-jdk-dir)/jre/lib
eclipse-src-dir = $(eclipse-jdk-dir)/src
define eclipse-ee-descriptor
# An Eclipse execution environment for the Avian JVM\
\n-Dee.executable=bin/java${exe-suffix}\
\n-Dee.bootclasspath=jre/lib/rt.jar\
\n-Dee.language.level=1.7\
\n-Dee.name=$(name)-$(version)-$(platform)-$(arch)$(options)\
\n-Dee.src=src\
\n-Dee.javadoc=file://$${ee.home}/doc\
\n-Djava.home=$${ee.home}\n
endef
else
eclipse-exec-env =
endif

.PHONY: build
ifneq ($(supports_avian_executable),false)
build: $(static-library) $(executable) $(dynamic-library) $(lzma-library) \
	$(lzma-encoder) $(executable-dynamic) $(classpath-dep) $(test-dep) \
	$(test-extra-dep) $(embed) $(build)/classpath.jar $(eclipse-exec-env)
else
build: $(static-library) $(dynamic-library) $(lzma-library) \
	$(lzma-encoder) $(classpath-dep) $(test-dep) \
	$(test-extra-dep) $(embed) $(build)/classpath.jar
endif

$(test-dep): $(classpath-dep)

$(test-extra-dep): $(classpath-dep)

.PHONY: run
run: build
	$(library-path) $(test-executable) $(test-args)

.PHONY: debug
debug: build
	$(library-path) $(db) $(test-executable) $(test-args)

.PHONY: vg
vg: build
	$(library-path) $(vg) $(test-executable) $(test-args)

.PHONY: test
test: build-test run-test

.PHONY: build-test
build-test: build $(build)/run-tests.sh $(build)/test.sh $(unittest-executable)

.PHONY: run-test
run-test:
ifneq ($(remote-test),true)
	/bin/sh $(build)/run-tests.sh
else
	@echo "running tests on $(remote-test-user)@$(remote-test-host):$(remote-test-port), in $(remote-test-dir)"
	rsync $(build) -rav --exclude '*.o' --rsh="ssh -p$(remote-test-port)" $(remote-test-user)@$(remote-test-host):$(remote-test-dir)
	ssh -p$(remote-test-port) $(remote-test-user)@$(remote-test-host) sh "$(remote-test-dir)/$(platform)-$(arch)$(options)/run-tests.sh"
endif

.PHONY: jdk-test
jdk-test: $(test-dep) $(build)/classpath.jar $(build)/jdk-run-tests.sh $(build)/test.sh
	/bin/sh $(build)/jdk-run-tests.sh

.PHONY: tarball
tarball:
	@echo "creating build/avian-$(version).tar.bz2"
	@mkdir -p build
	(cd .. && tar --exclude=build --exclude=cmake-build --exclude=distrib \
		--exclude=lib --exclude='.*' --exclude='*~' \
		-cjf avian/build/avian-$(version).tar.bz2 avian)

.PHONY: clean-current
clean-current:
	@echo "removing $(build)"
	rm -rf $(build)

.PHONY: clean
clean:
	@echo "removing build directories"
	rm -rf build cmake-build distrib lib

.PHONY: eclipse-ee
ifneq ($(strip $(eclipse-exec-env)),)
eclipse-ee: $(eclipse-ee-file) $(eclipse-lib-dir)/rt.jar $(eclipse-bin-dir)/java${exe-suffix} $(eclipse-src-dir)

$(eclipse-bin-dir):
	@mkdir -p $(@)

$(eclipse-lib-dir):
	@mkdir -p $(@)

$(eclipse-jdk-dir):
	@mkdir -p $(@)

$(eclipse-ee-file): $(eclipse-jdk-dir)
	@echo "writing eclipse execution environment descriptor to $(@)"
	@printf '${eclipse-ee-descriptor}' > $(@)

$(eclipse-src-dir): $(eclipse-jdk-dir)
	@echo "symlinking classpath for $(@)"
	@ln -sf ../../../../classpath $(@)

$(eclipse-bin-dir)/java$(exe-suffix): $(eclipse-bin-dir) $(executable)
	@echo "symlinking $(executable) for $(@)"
	@ln -sf ../../../$(name)${exe-suffix} $(@)

$(eclipse-lib-dir)/rt.jar: $(eclipse-lib-dir) $(build)/classpath.jar
	@echo "symlinking $(build)/classpath.jar for $(@)"
	@ln -sf ../../../../classpath.jar $(@)
else
eclipse-ee:
	$(error "Eclipse execution environment for platform '$(platform)' is not supported")
endif

ifeq ($(continuations),true)
$(build)/compile-x86-asm.o: $(src)/continuations-x86.$(asm-format)
endif

$(build)/run-tests.sh: $(test-classes) makefile $(build)/extra-dir/multi-classpath-test.txt $(build)/test/multi-classpath-test.txt
	echo 'cd $$(dirname $$0)' > $(@)
	echo "sh ./test.sh 2>/dev/null \\" >> $(@)
	echo "$(shell echo $(library-path) | sed 's|$(build)|\.|g') ./$(name)-unittest${exe-suffix} ./$(notdir $(test-executable)) $(mode) \"-Djava.library.path=. -cp test$(target-path-separator)extra-dir\" \\" >> $(@)
	echo "$(call class-names,$(test-build),$(filter-out $(test-support-classes), $(test-classes))) \\" >> $(@)
	echo "$(continuation-tests) $(tail-tests)" >> $(@)

$(build)/jdk-run-tests.sh: $(test-classes) makefile $(build)/extra-dir/multi-classpath-test.txt $(build)/test/multi-classpath-test.txt
	echo 'cd $$(dirname $$0)' > $(@)
	echo "sh ./test.sh 2>/dev/null \\" >> $(@)
	echo "'' true $(JAVA_HOME)/bin/java $(mode) \"-Xmx128m -Djava.library.path=. -cp test$(path-separator)extra-dir$(path-separator)classpath\" \\" >> $(@)
	echo "$(call class-names,$(test-build),$(filter-out $(test-support-classes), $(test-classes))) \\" >> $(@)
	echo "$(continuation-tests) $(tail-tests)" >> $(@)

$(build)/extra-dir/multi-classpath-test.txt:
	mkdir -p $(build)/extra-dir
	echo "$@" > $@

$(build)/test/multi-classpath-test.txt:
	echo "$@" > $@

$(build)/test.sh: $(test)/test.sh
	cp $(<) $(@)

gen-arg = $(shell echo $(1) | sed -e 's:$(build)/type-\(.*\)\.cpp:\1:')
$(generated-code): %.cpp: $(src)/types.def $(generator) $(classpath-dep)
	@echo "generating $(@)"
	@mkdir -p $(dir $(@))
	$(generator) -cp $(boot-classpath) -i $(<) -o $(@) -t $(call gen-arg,$(@))

$(classpath-dep): $(classpath-sources) $(classpath-jar-dep)
	@echo "compiling classpath classes"
	@mkdir -p $(classpath-build)
	$(javac) -source 1.$(java-version) -target 1.$(java-version) \
		-d $(classpath-build) -bootclasspath $(boot-classpath) \
		$(classpath-sources)
	@touch $(@)

$(test-build)/%.class: $(test)/%.java
	@echo $(<)

$(test-dep): $(test-sources) $(test-library)
	@echo "compiling test classes"
	@mkdir -p $(test-build)
	files="$(shell $(MAKE) -s --no-print-directory build=$(build) $(test-classes))"; \
	if test -n "$${files}"; then \
		$(javac) -source 1.$(java-version) -target 1.$(java-version) \
			-classpath $(test-build) -d $(test-build) -bootclasspath $(boot-classpath) $${files}; \
	fi
	$(javac) -source 1.2 -target 1.1 -XDjsrlimit=0 -d $(test-build) \
		-bootclasspath $(boot-classpath) test/Subroutine.java
	@touch $(@)

$(test-extra-dep): $(test-extra-sources)
	@echo "compiling extra test classes"
	@mkdir -p $(test-build)
	files="$(shell $(MAKE) -s --no-print-directory build=$(build) $(test-extra-classes))"; \
	if test -n "$${files}"; then \
		$(javac) -source 1.$(java-version) -target 1.$(java-version) \
			-d $(test-build) -bootclasspath $(boot-classpath) $${files}; \
	fi
	@touch $(@)

define compile-object
	@echo "compiling $(@)"
	@mkdir -p $(dir $(@))
	$(cxx) $(cflags) -c $$($(windows-path) $(<)) $(call output,$(@))
endef

define compile-asm-object
	@echo "compiling $(@)"
	@mkdir -p $(dir $(@))
	$(as) $(asmflags) $(call asm-output,$(@)) $(call asm-input,$(<))
endef

define compile-unittest-object
	@echo "compiling $(@)"
	@mkdir -p $(dir $(@))
	$(cxx) $(cflags) -c $$($(windows-path) $(<)) -I$(unittest) $(call output,$(@))
endef

$(vm-cpp-objects): $(build)/%.o: $(src)/%.cpp $(vm-depends)
	$(compile-object)

ifeq ($(process),interpret)
$(all-codegen-target-objects): $(build)/%.o: $(src)/%.cpp $(vm-depends)
	$(compile-object)
endif

$(unittest-objects): $(build)/unittest/%.o: $(unittest)/%.cpp $(vm-depends) $(unittest-depends)
	$(compile-unittest-object)

$(test-cpp-objects): $(test-build)/%.o: $(test)/%.cpp $(vm-depends)
	$(compile-object)

$(test-library): $(test-cpp-objects)
	@echo "linking $(@)"
ifdef ms_cl_compiler
	$(ld) $(shared) $(lflags) $(^) -out:$(@) \
		-debug -PDB:$(subst $(so-suffix),.pdb,$(@)) \
		-IMPLIB:$(test-build)/$(name).lib $(manifest-flags)
ifdef mt
	$(mt) -nologo -manifest $(@).manifest -outputresource:"$(@);2"
endif
else
	$(ld) $(^) $(shared) $(lflags) -o $(@)
endif

ifdef embed
$(embed): $(embed-objects) $(embed-loader-o)
	@echo "building $(embed)"
ifdef ms_cl_compiler
	$(ld) $(lflags) $(^) -out:$(@) \
		-debug -PDB:$(subst $(exe-suffix),.pdb,$(@)) $(manifest-flags)
ifdef mt
	$(mt) -nologo -manifest $(@).manifest -outputresource:"$(@);1"
endif
else
	$(cxx) $(^) $(lflags) $(static) $(call output,$(@))
endif

$(build-embed)/%.o: $(src)/%.cpp
	@echo "compiling $(@)"
	@mkdir -p $(dir $(@))
	$(cxx) $(cflags) -c $(<) $(call output,$(@))

$(embed-loader-o): $(embed-loader) $(converter)
	@mkdir -p $(dir $(@))
	$(converter) $(<) $(@) _binary_loader_start \
		_binary_loader_end $(target-format) $(arch)

$(embed-loader): $(embed-loader-objects) $(vm-objects) $(classpath-objects) \
		$(heapwalk-objects) $(lzma-decode-objects)

$(build-embed-loader)/%.o: $(src)/%.cpp
	@echo "compiling $(@)"
	@mkdir -p $(dir $(@))
	$(cxx) $(cflags) -c $(<) $(call output,$(@))
endif

$(build)/%.o: $(lzma)/C/%.c
	@echo "compiling $(@)"
	@mkdir -p $(dir $(@))
	$(cc) $(lzma-cflags) -c $$($(windows-path) $(<)) $(call output,$(@))

$(vm-asm-objects): $(build)/%-asm.o: $(src)/%.$(asm-format)
	$(compile-asm-object)

$(heapwalk-objects): $(build)/%.o: $(src)/%.cpp $(vm-depends)
	$(compile-object)

$(driver-object): $(driver-source)
	$(compile-object)

$(build)/main-dynamic.o: $(driver-source)
	@echo "compiling $(@)"
	@mkdir -p $(dir $(@))
	$(cxx) $(cflags) -DBOOT_LIBRARY=\"$(so-prefix)jvm$(so-suffix)\" \
		-c $(<) $(call output,$(@))

$(boot-object): $(boot-source)
	$(compile-object)

$(boot-javahome-object): $(src)/boot-javahome.cpp
	$(compile-object)

$(object-writer-objects) $(binary-to-object-objects): $(build)/%.o: $(src)/%.cpp $(binary-to-object-depends) $(object-writer-depends) $(all-depends)
	@mkdir -p $(dir $(@))
	$(build-cxx) $(converter-cflags) -c $(<) -o $(@)

$(converter): $(converter-objects) $(converter-tool-objects)
	@mkdir -p $(dir $(@))
	$(build-cc) $(^) -g -o $(@)

$(lzma-encoder-objects): $(build)/lzma/%.o: $(src)/lzma/%.cpp
	@mkdir -p $(dir $(@))
	$(build-cxx) $(lzma-build-cflags) -c $(<) -o $(@)

$(lzma-encoder): $(lzma-encoder-objects) $(lzma-encoder-lzma-objects)
	$(build-cc) $(^) -g -o $(@)

$(lzma-library): $(lzma-loader) $(lzma-decode-objects)
	@echo "creating $(@)"
	@rm -rf $(build)/libavian-lzma
	@mkdir -p $(build)/libavian-lzma
	rm -rf $(@)
	for x in $(^); \
		do cp $${x} $(build)/libavian-lzma/$$(echo $${x} | sed s:/:_:g); \
	done
ifdef ms_cl_compiler
	$(ar) $(arflags) $(build)/libavian-lzma/*.o -out:$(@)
else
	$(ar) cru $(@) $(build)/libavian-lzma/*.o
	$(ranlib) $(@)
endif

$(lzma-loader): $(src)/lzma/load.cpp
	$(compile-object)

$(build)/classpath.jar: $(classpath-dep) $(classpath-jar-dep)
	@echo "creating $(@)"
	(wd=$$(pwd) && \
	 cd $(classpath-build) && \
	 $(jar) c0f "$$($(native-path) "$${wd}/$(@)")" .)

$(classpath-object): $(build)/classpath.jar $(converter)
	@echo "creating $(@)"
	$(converter) $(<) $(@) _binary_classpath_jar_start \
		_binary_classpath_jar_end $(target-format) $(arch)

$(build)/javahome.jar:
	@echo "creating $(@)"
	(wd=$$(pwd) && \
	 cd "$(build-javahome)" && \
	 $(jar) c0f "$$($(native-path) "$${wd}/$(@)")" $(javahome-files))

$(javahome-object): $(build)/javahome.jar $(converter)
	@echo "creating $(@)"
	$(converter) $(<) $(@) _binary_javahome_jar_start \
		_binary_javahome_jar_end $(target-format) $(arch)

define compile-generator-object
	@echo "compiling $(@)"
	@mkdir -p $(dir $(@))
	$(build-cxx) -DPOINTER_SIZE=$(pointer-size) -O0 -g3 $(build-cflags) \
		-c $(<) -o $(@)
endef

$(generator-objects): $(generator-depends)
$(generator-objects): $(build)/%-build.o: $(src)/%.cpp
	$(compile-generator-object)

$(build)/%-build.o: $(lzma)/C/%.c
	@echo "compiling $(@)"
	@mkdir -p $(dir $(@))
	$(build-cc) -DPOINTER_SIZE=$(pointer-size) -O0 -g3 $(lzma-build-cflags) \
		-c $(<) -o $(@)

$(jni-objects): $(build)/%.o: $(classpath-src)/%.cpp $(vm-depends)
	$(compile-object)

$(static-library): $(vm-objects) $(classpath-objects) $(vm-heapwalk-objects) \
		$(javahome-object) $(boot-javahome-object) $(lzma-decode-objects)
	@echo "creating $(@)"
	@rm -rf $(build)/libavian
	@mkdir -p $(build)/libavian
	rm -rf $(@)
	for x in $(^); \
		do cp $${x} $(build)/libavian/$$(echo $${x} | sed s:/:_:g); \
	done
ifdef ms_cl_compiler
	$(ar) $(arflags) $(build)/libavian/*.o -out:$(@)
else
	$(ar) cru $(@) $(build)/libavian/*.o
	$(ranlib) $(@)
endif

executable-objects = $(vm-objects) $(classpath-objects) $(driver-object) \
	$(vm-heapwalk-objects) $(boot-object) $(vm-classpath-objects) \
	$(javahome-object) $(boot-javahome-object) $(lzma-decode-objects)

unittest-executable-objects = $(unittest-objects) $(vm-objects) \
	$(vm-heapwalk-objects) $(build)/util/arg-parser.o $(stub-objects) \
	$(lzma-decode-objects)

ifeq ($(process),interpret)
	unittest-executable-objects += $(all-codegen-target-objects)
endif

define link-executable
	@echo linking $(@)
	$(ld) $(^) $(rdynamic) $(lflags) $(classpath-lflags)  \
		-o $(@)
endef

$(executable): $(executable-objects)
	$(link-executable)

$(unittest-executable): $(unittest-executable-objects)
	$(link-executable)

$(dynamic-library): $(vm-objects) $(dynamic-object) $(classpath-objects) \
		$(vm-heapwalk-objects) $(boot-object) $(vm-classpath-objects) \
		$(classpath-libraries) $(javahome-object) $(boot-javahome-object) \
		$(lzma-decode-objects)
	@echo "linking $(@)"
ifdef ms_cl_compiler
	$(ld) $(shared) $(lflags) $(^) -out:$(@) \
		-debug -PDB:$(subst $(so-suffix),.pdb,$(@)) \
		-IMPLIB:$(subst $(so-suffix),.lib,$(@)) $(manifest-flags)
ifdef mt
	$(mt) -nologo -manifest $(@).manifest -outputresource:"$(@);2"
endif
else
	$(ld) $(^) $(version-script-flag) $(soname-flag) \
		$(shared) $(lflags) $(classpath-lflags) $(bootimage-lflags) \
		-o $(@)
endif
	$(strip) $(strip-all) $(@)

# todo: the $(no-lto) flag below is due to odd undefined reference errors on
# Ubuntu 11.10 which may be fixable without disabling LTO.
$(executable-dynamic): $(driver-dynamic-objects) $(dynamic-library)
	@echo "linking $(@)"
ifdef ms_cl_compiler
	$(ld) $(lflags) -LIBPATH:$(build) -DEFAULTLIB:$(name) \
		-debug -PDB:$(subst $(exe-suffix),.pdb,$(@)) \
		$(driver-dynamic-objects) -out:$(@) $(manifest-flags)
ifdef mt
	$(mt) -nologo -manifest $(@).manifest -outputresource:"$(@);1"
endif
else
	$(ld) $(driver-dynamic-objects) -L$(build) -ljvm $(lflags) $(no-lto) $(rpath) -o $(@)
endif
	$(strip) $(strip-all) $(@)

$(generator): $(generator-objects) $(generator-lzma-objects)
	@echo "linking $(@)"
	$(build-ld-cpp) $(^) $(build-lflags) $(static-on-windows) -o $(@)

$(openjdk-objects): $(build)/openjdk/%-openjdk.o: $(openjdk-src)/%.c \
		$(openjdk-headers-dep)
	@echo "compiling $(@)"
	@mkdir -p $(dir $(@))
	sed 's/^static jclass ia_class;//' < $(<) > $(build)/openjdk/$(notdir $(<))
ifeq ($(platform),ios)
	sed \
		-e 's/^#ifndef __APPLE__/#if 1/' \
		-e 's/^#ifdef __APPLE__/#if 0/' \
		< "$(openjdk-src)/solaris/native/java/lang/ProcessEnvironment_md.c" \
		> $(build)/openjdk/ProcessEnvironment_md.c
	sed \
		-e 's/^#ifndef __APPLE__/#if 1/' \
		-e 's/^#ifdef __APPLE__/#if 0/' \
		< "$(openjdk-src)/solaris/native/java/lang/UNIXProcess_md.c" \
		> $(build)/openjdk/UNIXProcess_md.c
	if [ -e "$(openjdk-src)/solaris/native/java/lang/childproc.h" ]; then \
		sed \
			-e 's/^#ifndef __APPLE__/#if 1/' \
			-e 's/^#ifdef __APPLE__/#if 0/' \
			< "$(openjdk-src)/solaris/native/java/lang/childproc.h" \
			> $(build)/openjdk/childproc.h; \
	fi
endif
ifneq (7,$(openjdk-version))
	if [ -f openjdk-patches/$(notdir $(<)).8.patch ]; then \
		( cd $(build) && patch -p0 ) < openjdk-patches/$(notdir $(<)).8.patch; \
	fi
	if [ -f openjdk-patches/$(notdir $(<)).8.$(platform).patch ]; then \
		( cd $(build) && patch -p0 ) < openjdk-patches/$(notdir $(<)).8.$(platform).patch; \
	fi
endif
	if [ -f openjdk-patches/$(notdir $(<)).patch ]; then \
		( cd $(build) && patch -p0 ) < openjdk-patches/$(notdir $(<)).patch; \
	fi
	$(cc) -fPIC $(openjdk-extra-cflags) $(openjdk-cflags) \
		$(optimization-cflags) -w -c $(build)/openjdk/$(notdir $(<)) \
		$(call output,$(@)) -Wno-return-type


$(openjdk-local-objects): $(build)/openjdk/%-openjdk.o: $(src)/openjdk/%.c \
		$(openjdk-headers-dep)
	@echo "compiling $(@)"
	@mkdir -p $(dir $(@))
	$(cc) -fPIC $(openjdk-extra-cflags) $(openjdk-cflags) \
		$(optimization-cflags) -w -c $(<) $(call output,$(@))

$(openjdk-headers-dep):
	@echo "generating openjdk headers"
	@mkdir -p $(dir $(@))
	$(javah) -d $(build)/openjdk -bootclasspath $(boot-classpath) \
		$(openjdk-headers-classes)

$(openjdk-jar-dep):
	@echo "extracting openjdk classes"
	@mkdir -p $(dir $(@))
	@mkdir -p $(classpath-build)
	(cd $(classpath-build) && \
		$(jar) xf "$$($(native-path) "$(openjdk)/jre/lib/rt.jar")" && \
		$(jar) xf "$$($(native-path) "$(openjdk)/jre/lib/jsse.jar")" && \
		$(jar) xf "$$($(native-path) "$(openjdk)/jre/lib/jce.jar")" && \
		$(jar) xf "$$($(native-path) "$(openjdk)/jre/lib/charsets.jar")" && \
		$(jar) xf "$$($(native-path) "$(openjdk)/jre/lib/ext/sunjce_provider.jar")" && \
		$(jar) xf "$$($(native-path) "$(openjdk)/jre/lib/resources.jar")")
	@touch $(@)