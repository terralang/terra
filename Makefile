
# If the defaults for LLVM_CONFIG are not right for your installation
# create a Makefile.inc file and point LLVM_CONFIG at the llvm-config binary for your llvm distribution
# If you want to enable cuda compiler support is enabled if the path specified by
# CUDA_HOME exists

-include Makefile.inc

# Debian packages name llvm-config with a version number - list them here in preference order
LLVM_CONFIG ?= $(shell which llvm-config-3.5 llvm-config | head -1)
#luajit will be downloaded automatically (it's much smaller than llvm)
#to override this, set LUAJIT_PREFIX to the home of an already installed luajit
LUAJIT_PREFIX ?= build

# same with clang
CLANG ?= $(shell which clang-3.5 clang | head -1)

CXX ?= $(CLANG)++
CC ?= $(CLANG)

LLVM_PREFIX = $(shell $(LLVM_CONFIG) --prefix)

#if clang is not installed in the same prefix as llvm
#then use the clang in the caller's path
ifeq ($(wildcard $(LLVM_PREFIX)/bin/clang),)
CLANG_PREFIX ?= $(dir $(CLANG))..
else
CLANG_PREFIX ?= $(LLVM_PREFIX)
endif

CUDA_HOME ?= /usr/local/cuda
ENABLE_CUDA ?= $(shell test -e $(CUDA_HOME) && echo 1 || echo 0)

.SUFFIXES:
.SECONDARY:
UNAME := $(shell uname)


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

LUAJIT_VERSION_BASE ?= 2.0
LUAJIT_VERSION_EXTRA ?= .5
LUAJIT_VERSION ?= LuaJIT-$(LUAJIT_VERSION_BASE)$(LUAJIT_VERSION_EXTRA)
LUAJIT_EXECUTABLE ?= luajit-$(LUAJIT_VERSION_BASE)$(LUAJIT_VERSION_EXTRA)
LUAJIT_URL ?= http://luajit.org/download/$(LUAJIT_VERSION).tar.gz
LUAJIT_TAR ?= $(LUAJIT_VERSION).tar.gz
LUAJIT_DIR ?= build/$(LUAJIT_VERSION)
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
ifneq ($(LLVM_VERSION), 32)
CPPFLAGS += -std=c++11
endif


ifneq ($(findstring $(UNAME), Linux FreeBSD),)
DYNFLAGS = -shared -fPIC
TERRA_STATIC_LIBRARY += -Wl,-export-dynamic -Wl,--whole-archive $(LIBRARY) -Wl,--no-whole-archive
else
DYNFLAGS = -dynamiclib -single_module -fPIC -install_name "@rpath/terra.dylib"
TERRA_STATIC_LIBRARY =  -Wl,-force_load,$(LIBRARY)
endif

LLVM_LIBRARY_FLAGS += $(LUAJIT_LIB)
LLVM_LIBRARY_FLAGS += $(shell $(LLVM_CONFIG) --ldflags) -L$(CLANG_PREFIX)/lib
LLVM_LIBRARY_FLAGS += -lclangFrontend -lclangDriver \
                      -lclangSerialization -lclangCodeGen -lclangParse -lclangSema \
                      -lclangAnalysis \
                      -lclangEdit -lclangAST -lclangLex -lclangBasic

CLANG_REWRITE_CORE = "32 33 34"
ifneq (,$(findstring $(LLVM_VERSION),$(CLANG_REWRITE_CORE)))
LLVM_LIBRARY_FLAGS += -lclangRewriteCore
endif

# by default, Terra includes only the pieces of the LLVM libraries it needs,
#  but this can be a problem if third-party-libraries that also need LLVM are
#  used - allow the user to request that some/all of the LLVM components be
#  included and re-exported in their entirety
ifeq "$(LLVMVERGT4)" "1"
    LLVM_LIBS += $(shell $(LLVM_CONFIG) --libs --link-static)
else
	LLVM_LIBS += $(shell $(LLVM_CONFIG) --libs)
endif
ifneq ($(REEXPORT_LLVM_COMPONENTS),)
  REEXPORT_LIBS := $(shell $(LLVM_CONFIG) --libs $(REEXPORT_LLVM_COMPONENTS))
  ifneq ($(findstring $(UNAME), Linux FreeBSD),)
    LLVM_LIBRARY_FLAGS += -Wl,--whole-archive $(REEXPORT_LIBS) -Wl,--no-whole-archive
  else
    LLVM_LIBRARY_FLAGS += $(REEXPORT_LIBS:%=-Wl,-force_load,%)
  endif
  LLVM_LIBRARY_FLAGS += $(filter-out $(REEXPORT_LIBS),$(LLVM_LIBS))
else
  LLVM_LIBRARY_FLAGS += $(LLVM_LIBS)
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

PACKAGE_DEPS += $(LUAJIT_LIB)

#makes luajit happy on osx 10.6 (otherwise luaL_newstate returns NULL)
ifeq ($(UNAME), Darwin)
LFLAGS += -pagezero_size 10000 -image_base 100000000 
endif

CLANG_RESOURCE_DIRECTORY=$(CLANG_PREFIX)/lib/clang/$(LLVM_VERSION_NUM)

ifeq ($(ENABLE_CUDA),1)
CUDA_INCLUDES = -DTERRA_ENABLE_CUDA -I $(CUDA_HOME)/include -I $(CUDA_HOME)/nvvm/include
FLAGS += $(CUDA_INCLUDES)
endif

ifeq (OFF,$(shell $(LLVM_CONFIG) --assertion-mode))
FLAGS += -DTERRA_LLVM_HEADERS_HAVE_NDEBUG
endif

LIBOBJS = tkind.o tcompiler.o tllvmutil.o tcwrapper.o tinline.o terra.o lparser.o lstring.o lobject.o lzio.o llex.o lctype.o treadnumber.o tcuda.o tdebug.o tinternalizedfiles.o lj_strscan.o
LIBLUA = terralib.lua strict.lua cudalib.lua asdl.lua

EXEOBJS = main.o linenoise.o

EMBEDDEDLUA = $(addprefix build/,$(LIBLUA:.lua=.h))
GENERATEDHEADERS = $(EMBEDDEDLUA) build/clangpaths.h build/internalizedfiles.h

LUAHEADERS = lua.h lualib.h lauxlib.h luaconf.h

OBJS = $(LIBOBJS) $(EXEOBJS)

EXECUTABLE = release/bin/terra
LIBRARY = release/lib/libterra.a
LIBRARY_NOLUA = release/lib/libterra_nolua.a
LIBRARY_NOLUA_NOLLVM = release/lib/libterra_nolua_nollvm.a
LIBRARY_VARIANTS = $(LIBRARY_NOLUA) $(LIBRARY_NOLUA_NOLLVM)
ifeq ($(UNAME), Darwin)
DYNLIBRARY = release/lib/terra.dylib
else
DYNLIBRARY = release/lib/terra.so
endif
RELEASE_HEADERS = $(addprefix release/include/terra/,$(LUAHEADERS))
BIN2C = build/bin2c

#put any install-specific stuff in here
-include Makefile.inc

.PHONY:	all clean download purge test release install
all:	$(EXECUTABLE) $(DYNLIBRARY)

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
	curl $(LUAJIT_URL) -o build/$(LUAJIT_TAR)
else
	wget $(LUAJIT_URL) -O build/$(LUAJIT_TAR)
endif

build/lib/libluajit-5.1.a: build/$(LUAJIT_TAR)
	(cd build; tar -xf $(LUAJIT_TAR))
	(cd $(LUAJIT_DIR); $(MAKE) install PREFIX=$(realpath build) CC=$(CC) STATIC_CC="$(CC) -fPIC")

release/include/terra/%.h:  $(LUAJIT_INCLUDE)/%.h $(LUAJIT_LIB) 
	cp $(LUAJIT_INCLUDE)/$*.h $@
    
build/llvm_objects/llvm_list:    $(addprefix build/, $(LIBOBJS) $(EXEOBJS))
	mkdir -p build/llvm_objects/luajit
	$(CXX) -o /dev/null $(addprefix build/, $(LIBOBJS) $(EXEOBJS)) $(LLVM_LIBRARY_FLAGS) $(SUPPORT_LIBRARY_FLAGS) $(LFLAGS) -Wl,-t 2>&1 | egrep "lib(LLVM|clang)"  > build/llvm_objects/llvm_list
	# extract needed LLVM objects based on a dummy linker invocation
	< build/llvm_objects/llvm_list $(LUAJIT) src/unpacklibraries.lua build/llvm_objects
	# include all luajit objects, since the entire lua interface is used in terra 


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

#run clang on a C file to extract the header search paths for this architecture
#genclangpaths.lua find the path arguments and formats them into a C file that is included by the cwrapper
#to configure the paths	
build/clangpaths.h:	src/dummy.c $(PACKAGE_DEPS) src/genclangpaths.lua
	$(LUAJIT) src/genclangpaths.lua $@ $(CLANG) $(CUDA_INCLUDES)

build/internalizedfiles.h:	$(PACKAGE_DEPS) src/geninternalizedfiles.lua lib/std.t lib/parsing.t
	$(LUAJIT) src/geninternalizedfiles.lua $@  $(CLANG_RESOURCE_DIRECTORY) "%.h$$" $(CLANG_RESOURCE_DIRECTORY) "%.modulemap$$" lib "%.t$$" 

clean:
	rm -rf build/*.o build/*.d $(GENERATEDHEADERS)
	rm -rf $(EXECUTABLE) terra $(LIBRARY) $(LIBRARY_NOLUA) $(LIBRARY_NOLUA_NOLLVM) $(DYNLIBRARY) $(RELEASE_HEADERS) build/llvm_objects build/lua_objects

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
