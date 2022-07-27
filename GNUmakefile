
# If the defaults for LLVM_CONFIG are not right for your installation
# create a Makefile.inc file and point LLVM_CONFIG at the llvm-config binary for your llvm distribution
# If you want to enable cuda compiler support is enabled if the path specified by
# CUDA_HOME exists

-include Makefile.inc

# Debian packages name llvm-config with a version number - list them here in preference order
LLVM_CONFIG ?= $(shell which llvm-config13 llvm-config14 llvm-config false | head -1)
#luajit will be downloaded automatically (it's much smaller than llvm)
#to override this, set LUAJIT_PREFIX to the home of an already installed luajit
LUAJIT_PREFIX ?= build

# same with clang
CLANG ?= $(shell which clang-3.5 clang false | head -1)

CXX ?= $(CLANG)++
CC ?= $(CLANG)

LLVM_PREFIX = $(shell $(LLVM_CONFIG) --prefix)

#if clang is not installed in the same prefix as llvm
#then use the clang in the caller's path
ifeq ($(wildcard $(LLVM_PREFIX)/bin/clang),)
CLANG_PREFIX ?= $(dir $(shell $(CLANG) --version |awk '$$1 == "InstalledDir:" { print$$2 }'))
else
CLANG_PREFIX ?= $(LLVM_PREFIX)
endif

CUDA_HOME ?= /usr/local/cuda
ENABLE_CUDA ?= $(shell test -e $(CUDA_HOME) && echo 1 || echo 0)

.SUFFIXES:
.SECONDARY:
UNAME := $(shell uname)


PKG_CONFIG = $(shell which pkg-config false | head -1)

AR = ar
LD = ld
FLAGS += -Wall -g -fPIC
LFLAGS = -g

# The -E flag is BSD-specific. It is supported (though undocumented)
# on certain newer versions of GNU Sed, but not all. Check for -E
# support and otherwise fall back to the GNU Sed flag -r.
SED_E = sed -E
ifeq ($(shell sed -E '' </dev/null >/dev/null 2>&1 && echo yes || echo no),no)
SED_E = sed -r
endif

TERRA_VERSION_RAW=$(shell git describe --tags 2>/dev/null || echo unknown)
TERRA_VERSION=$(shell echo "$(TERRA_VERSION_RAW)" | $(SED_E) 's/^release-//')
FLAGS += -DTERRA_VERSION_STRING="\"$(TERRA_VERSION)\""

# Add the following lines to Makefile.inc to switch to LuaJIT-2.1 beta releases
#LUAJIT_VERSION_BASE =2.1
#LUAJIT_VERSION_EXTRA =.0-beta2

LUAJIT_VERSION_BASE ?= 2.1
LUAJIT_VERSION_EXTRA ?= .0-beta3
LUAJIT_VERSION ?= LuaJIT-$(LUAJIT_VERSION_BASE)$(LUAJIT_VERSION_EXTRA)
LUAJIT_EXECUTABLE ?= luajit-$(LUAJIT_VERSION_BASE)$(LUAJIT_VERSION_EXTRA)
LUAJIT_COMMIT ?= 50936d784474747b4569d988767f1b5bab8bb6d0
ifneq ($(strip $(LUAJIT_COMMIT)),)
LUAJIT_URL ?= https://github.com/LuaJIT/LuaJIT/archive/$(LUAJIT_COMMIT).tar.gz
LUAJIT_TAR ?= LuaJIT-$(LUAJIT_COMMIT).tar.gz
LUAJIT_DIR ?= build/LuaJIT-$(LUAJIT_COMMIT)
else
LUAJIT_URL ?= http://luajit.org/download/$(LUAJIT_VERSION).tar.gz
LUAJIT_TAR ?= $(LUAJIT_VERSION).tar.gz
LUAJIT_DIR ?= build/$(LUAJIT_VERSION)
endif
LUAJIT_LIB ?= $(LUAJIT_PREFIX)/lib/libluajit-5.1.a
LUAJIT_INCLUDE ?= $(dir $(shell ls 2>/dev/null $(LUAJIT_PREFIX)/include/luajit-$(LUAJIT_VERSION_BASE)/lua.h || ls 2>/dev/null $(LUAJIT_PREFIX)/include/lua.h || echo $(LUAJIT_PREFIX)/include/luajit-$(LUAJIT_VERSION_BASE)/lua.h))
LUAJIT ?= $(LUAJIT_PREFIX)/bin/$(LUAJIT_EXECUTABLE)

FLAGS += -I build -I $(LUAJIT_INCLUDE) -I release/include/terra  -I $(shell $(LLVM_CONFIG) --includedir) -I $(CLANG_PREFIX)/include

FLAGS += -D_GNU_SOURCE -D__STDC_CONSTANT_MACROS -D__STDC_FORMAT_MACROS -D__STDC_LIMIT_MACROS -O0 -fno-common -Wcast-qual
CPPFLAGS = -fno-rtti -Woverloaded-virtual -fvisibility-inlines-hidden

LLVM_VERSION_NUM=$(shell $(LLVM_CONFIG) --version | sed -e s/svn//)
LLVM_VERSION=$(shell echo $(LLVM_VERSION_NUM) | $(SED_E) 's/^([0-9]+)\.([0-9]+).*/\1\2/')
LLVMVERGT4 := $(shell expr $(LLVM_VERSION) \>= 40)

FLAGS += -DLLVM_VERSION=$(LLVM_VERSION)

LLVM_NEEDS_CXX14="100 110 111 120 130 140"
ifneq (,$(findstring $(LLVM_VERSION),$(LLVM_NEEDS_CXX14)))
CPPFLAGS += -std=c++1y # GCC 5 does not support -std=c++14 flag
else
CPPFLAGS += -std=c++11
endif

ifneq ($(findstring $(UNAME), Linux FreeBSD),)
DYNFLAGS = -shared -fPIC
TERRA_STATIC_LIBRARY += -Wl,-export-dynamic -Wl,--whole-archive $(LIBRARY) -Wl,--no-whole-archive
else
DYNFLAGS = -dynamiclib -single_module -fPIC -install_name "@rpath/libterra.dylib"
TERRA_STATIC_LIBRARY =  -Wl,-force_load,$(LIBRARY)
endif

CLANG_LIBS += libclangFrontend.a \
	libclangDriver.a \
	libclangSerialization.a \
	libclangCodeGen.a \
	libclangParse.a \
	libclangSema.a \
	libclangAnalysis.a \
	libclangEdit.a \
	libclangAST.a \
	libclangLex.a \
	libclangBasic.a

CLANG_AST_MATCHERS = "80 90 100 110 111 120 130 140"
ifneq (,$(findstring $(LLVM_VERSION),$(CLANG_AST_MATCHERS)))
CLANG_LIBS += libclangASTMatchers.a
endif

# Get full path to clang libaries
CLANG_LIBFILES := $(patsubst %, $(CLANG_PREFIX)/lib/%, $(CLANG_LIBS))

ifeq "$(LLVMVERGT4)" "1"
    LLVM_LIBS += $(shell $(LLVM_CONFIG) --libs --link-static)
	LLVM_LIBFILES := $(shell $(LLVM_CONFIG) --libfiles --link-static)
else
	LLVM_LIBS += $(shell $(LLVM_CONFIG) --libs)
	LLVM_LIBFILES := $(shell $(LLVM_CONFIG) --libfiles)
endif

LLVM_POLLY = "100 110 111 120 130 140"
ifneq (,$(findstring $(LLVM_VERSION),$(LLVM_POLLY)))
	LLVM_LIBFILES += $(shell $(LLVM_CONFIG) --libdir)/libPolly*.a
endif

# llvm sometimes requires ncurses and libz, check if they have the symbols, and add them if they do
ifeq ($(shell nm $(LLVM_PREFIX)/lib/libLLVMSupport.a | grep setupterm >/dev/null 2>&1; echo $$?), 0)
    SUPPORT_LIBRARY_FLAGS += -lcurses 
endif
ifeq ($(shell nm $(LLVM_PREFIX)/lib/libLLVMSupport.a | grep compress2 >/dev/null 2>&1; echo $$?), 0)
    SUPPORT_LIBRARY_FLAGS += -lz
endif

ifeq ($(UNAME), Linux)
SUPPORT_LIBRARY_FLAGS += -ldl -pthread
endif
ifeq ($(UNAME), FreeBSD)
SUPPORT_LIBRARY_FLAGS += -lexecinfo -pthread
endif

LIBFFI_LIBS = $(shell $(PKG_CONFIG) --libs libffi)
FLAGS += $(shell $(PKG_CONFIG) --cflags libffi)
ifeq ($(LIBFFI_LIBS),)
$(error libffi is not installed)
endif

LIBXML20_LIBS = $(shell $(PKG_CONFIG) --libs libxml-2.0)
FLAGS += $(shell $(PKG_CONFIG) --cflags libxml-2.0)
ifeq ($(LIBXML20_LIBS),)
$(error libxml-2.0 is not installed)
endif

LIBEDIT_LIBS = $(shell $(PKG_CONFIG) --libs libedit)
FLAGS += $(shell $(PKG_CONFIG) --cflags libedit)
ifeq ($(LIBEDIT_LIBS),)
$(error libedit is not installed)
endif

SUPPORT_LIBRARY_FLAGS += $(LIBFFI_LIBS) $(LIBXML20_LIBS) $(LIBEDIT_LIBS)

PACKAGE_DEPS += $(LUAJIT_LIB)

CLANG_RESOURCE_DIRECTORY=$(CLANG_PREFIX)/lib/clang/$(LLVM_VERSION_NUM)

ifeq ($(ENABLE_CUDA),1)
CUDA_INCLUDES = -DTERRA_ENABLE_CUDA -I $(CUDA_HOME)/include -I $(CUDA_HOME)/nvvm/include
FLAGS += $(CUDA_INCLUDES)
endif

ifeq (OFF,$(shell $(LLVM_CONFIG) --assertion-mode))
FLAGS += -DTERRA_LLVM_HEADERS_HAVE_NDEBUG
endif

LIBOBJS = tkind.o tcompiler.o tllvmutil.o tcwrapper.o tinline.o terra.o lparser.o lstring.o lobject.o lzio.o llex.o lctype.o treadnumber.o tcuda.o tdebug.o tinternalizedfiles.o lj_strscan.o
LIBLUA = terralib.lua strict.lua cudalib.lua asdl.lua terralist.lua

EXEOBJS = main.o linenoise.o

EMBEDDEDLUA = $(addprefix build/,$(LIBLUA:.lua=.h))
GENERATEDHEADERS = $(EMBEDDEDLUA) build/internalizedfiles.h

LUAHEADERS = lua.h lualib.h lauxlib.h luaconf.h

OBJS = $(LIBOBJS) $(EXEOBJS)

EXECUTABLE = release/bin/terra
LIBRARY = release/lib/libterra.a
LIBRARY_NOLUA = release/lib/libterra_nolua.a
LIBRARY_NOLUA_NOLLVM = release/lib/libterra_nolua_nollvm.a
LIBRARY_VARIANTS = $(LIBRARY_NOLUA) $(LIBRARY_NOLUA_NOLLVM)
ifeq ($(UNAME), Darwin)
DYNLIBRARY = release/lib/libterra.dylib
DYNLIBRARY_LINK = release/lib/terra.dylib
else
DYNLIBRARY = release/lib/libterra.so
DYNLIBRARY_LINK = release/lib/terra.so
endif
RELEASE_HEADERS = $(addprefix release/include/terra/,$(LUAHEADERS))
BIN2C = build/bin2c

#put any install-specific stuff in here
-include Makefile.inc

.PHONY:	all clean download purge test release install
all:	$(EXECUTABLE) $(DYNLIBRARY) $(DYNLIBRARY_LINK)

test:	all
	(cd tests; ./run)

variants:	$(LIBRARY_VARIANTS)

build/%.o:	src/%.cpp $(PACKAGE_DEPS)
	$(CXX) $(FLAGS) $(CPPFLAGS) $< -c -o $@

build/%.o:	src/%.c $(PACKAGE_DEPS)
	$(CC) $(FLAGS) $< -c -o $@

download: build/$(LUAJIT_TAR)

build/$(LUAJIT_TAR):
ifeq ($(UNAME), Darwin)
	curl -L $(LUAJIT_URL) -o build/$(LUAJIT_TAR)
else
	wget $(LUAJIT_URL) -O build/$(LUAJIT_TAR)
endif

build/lib/libluajit-5.1.a: build/$(LUAJIT_TAR)
	(cd build; tar -xf $(LUAJIT_TAR))
	# MACOSX_DEPLOYMENT_TARGET is a workaround for https://github.com/LuaJIT/LuaJIT/issues/484
	# see also https://github.com/LuaJIT/LuaJIT/issues/575
	(cd $(LUAJIT_DIR); $(MAKE) install PREFIX=$(realpath build) CC=$(CC) STATIC_CC="$(CC) -fPIC" XCFLAGS=-DLUAJIT_ENABLE_GC64 MACOSX_DEPLOYMENT_TARGET=10.7)

release/include/terra/%.h:  $(LUAJIT_INCLUDE)/%.h $(LUAJIT_LIB) 
	cp $(LUAJIT_INCLUDE)/$*.h $@
    
build/llvm_objects/llvm_list:    $(addprefix build/, $(LIBOBJS) $(EXEOBJS))
	mkdir -p build/llvm_objects/luajit
	# Extract Luajit + all LLVM & Clang libraries
	cd build/llvm_objects; for lib in $(LUAJIT_LIB) $(LLVM_LIBFILES) $(CLANG_LIBFILES); do \
		echo Extracing objects from $$lib; \
		DIR=$$(basename $$lib .a); \
		mkdir -p $$DIR; \
		cd $$DIR; \
		ar x $$lib; \
		cd ..; \
	done

build/lua_objects/lj_obj.o:    $(LUAJIT_LIB)
	mkdir -p build/lua_objects
	cd build/lua_objects; ar x $(realpath $(LUAJIT_LIB))

$(LIBRARY):	$(RELEASE_HEADERS) $(addprefix build/, $(LIBOBJS)) build/llvm_objects/llvm_list build/lua_objects/lj_obj.o
	mkdir -p release/lib
	rm -f $@
	$(AR) -cq $@ $(addprefix build/, $(LIBOBJS)) build/llvm_objects/*/*.o build/lua_objects/*.o
	ranlib $@

$(LIBRARY_NOLUA): 	$(RELEASE_HEADERS) $(addprefix build/, $(LIBOBJS)) build/llvm_objects/llvm_list
	mkdir -p release/lib
	rm -f $@
	$(AR) -cq $@ $(addprefix build/, $(LIBOBJS)) build/llvm_objects/*/*.o

$(LIBRARY_NOLUA_NOLLVM):	$(RELEASE_HEADERS) $(addprefix build/, $(LIBOBJS))
	mkdir -p release/lib
	rm -f $@
	$(AR) -cq $@ $(addprefix build/, $(LIBOBJS))

$(DYNLIBRARY):	$(LIBRARY)
	$(CXX) $(DYNFLAGS) $(TERRA_STATIC_LIBRARY) $(SUPPORT_LIBRARY_FLAGS) -o $@  

$(DYNLIBRARY_LINK):	$(DYNLIBRARY)
	ln -s $(notdir $(DYNLIBRARY)) $(DYNLIBRARY_LINK)

$(EXECUTABLE):	$(addprefix build/, $(EXEOBJS)) $(LIBRARY)
	mkdir -p release/bin release/lib
	$(CXX) $(addprefix build/, $(EXEOBJS)) -o $@ $(LFLAGS) $(TERRA_STATIC_LIBRARY)  $(SUPPORT_LIBRARY_FLAGS)
	if [ ! -e terra  ]; then ln -s $(EXECUTABLE) terra; fi;

$(BIN2C):	src/bin2c.c
	$(CC) -O3 -o $@ $<


#rule for packaging lua code into a header file
build/%.bc:	src/%.lua $(PACKAGE_DEPS)
	$(LUAJIT) -bg $< $@
build/%.h:	build/%.bc $(PACKAGE_DEPS)
	$(LUAJIT) src/genheader.lua $< $@

build/internalizedfiles.h:	$(PACKAGE_DEPS) src/geninternalizedfiles.lua lib/std.t lib/parsing.t
	$(LUAJIT) src/geninternalizedfiles.lua $@  $(CLANG_RESOURCE_DIRECTORY) "%.h$$" $(CLANG_RESOURCE_DIRECTORY) "%.modulemap$$" lib "%.t$$" 

clean:
	rm -rf build/*.o build/*.d $(GENERATEDHEADERS)
	rm -rf $(EXECUTABLE) terra $(LIBRARY) $(LIBRARY_NOLUA) $(LIBRARY_NOLUA_NOLLVM) $(DYNLIBRARY) $(DYNLIBRARY_LINK) $(RELEASE_HEADERS) build/llvm_objects build/lua_objects

purge:	clean
	rm -rf build/*

TERRA_SHARE_PATH=release/share/terra

RELEASE_NAME := terra-`uname | sed -e s/Darwin/OSX/ | sed -e s/CYGWIN.*/Windows/`-`uname -m`-`git rev-parse --short HEAD`
release:
	for i in `git ls-tree HEAD -r tests --name-only`; do mkdir -p $(TERRA_SHARE_PATH)/`dirname $$i`; cp $$i $(TERRA_SHARE_PATH)/$$i; done;
	mv release $(RELEASE_NAME)
	zip -q -r $(RELEASE_NAME).zip $(RELEASE_NAME)
	mv $(RELEASE_NAME) release

PREFIX ?= /usr/local
install: all
	cp -R release/* $(PREFIX)

# dependency rules
DEPENDENCIES = $(patsubst %.o,build/%.d,$(OBJS))
build/%.d:	src/%.cpp $(PACKAGE_DEPS) $(GENERATEDHEADERS)
	@$(CXX) $(FLAGS) $(CPPFLAGS) -w -MM -MT '$@ $(@:.d=.o)' $< -o $@
build/%.d:	src/%.c $(PACKAGE_DEPS) $(GENERATEDHEADERS)
	@$(CC) $(FLAGS) -w -MM -MT '$@ $(@:.d=.o)' $< -o $@

#if we are cleaning, then don't include dependencies (which would require the header files are built)	
ifeq ($(findstring $(MAKECMDGOALS),download purge clean release),)
-include $(DEPENDENCIES)
endif
