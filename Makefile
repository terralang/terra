############################
# Configurable options
############################

# If the defaults for LLVM_CONFIG are not right for your installation
# create a Makefile.inc file and point LLVM_CONFIG at the llvm-config binary for your llvm distribution
# If you want to enable cuda compiler support is enabled if the path specified by
# CUDA_HOME exists

-include Makefile.inc

# customizable install prefixes
PREFIX ?= /usr/local
INSTALL_BINARY_DIR ?= $(PREFIX)/bin
INSTALL_LIBRARY_DIR ?= $(PREFIX)/lib
INSTALL_SHARE_DIR ?= $(PREFIX)/share
INSTALL_INCLUDE_DIR ?= $(PREFIX)/include
INSTALL_LUA_LIBRARY_DIR ?= $(PREFIX)/lib

# Debian packages name llvm-config with a version number - list them here in preference order
LLVM_CONFIG ?= $(shell which llvm-config-3.5 llvm-config | head -1)
#luajit will be downloaded automatically (it's much smaller than llvm)
#to override this, set LUAJIT_PREFIX to the home of an already installed luajit
LUAJIT_PREFIX ?= build

# same with clang
CLANG ?= $(shell which clang-3.5 clang | head -1)

CXX ?= $(CLANG)++
CC ?= $(CLANG)

PIC_FLAG ?= -fPIC
FLAGS=$(CFLAGS)

# top-level build rule, must be first
EXECUTABLE = release/bin/terra
DYNLIBRARY = release/lualib/terra.so
.PHONY:	all clean purge test release install
all:	$(EXECUTABLE) $(DYNLIBRARY)

UNAME := $(shell uname)
ifeq ($(UNAME), Darwin)
WGET = curl -o
LUA_TARGET = macosx
else
WGET = wget -O
LUA_TARGET = linux
endif

ifneq ($(TERRA_RPATH),)
TERRA_RPATH_FLAGS = -Wl,-rpath $(TERRA_RPATH)
endif

###########################
# Sanity Checks
###########################

ifeq (,$(wildcard $(CLANG)))
    $(error clang could not be found; please set the CLANG and LLVM_CONFIG variables)
endif

ifeq (,$(wildcard $(LLVM_CONFIG)))
    $(error llvm-config could not be found; please set the CLANG and LLVM_CONFIG variables)
endif

############################
# Rules for building Lua/JIT
############################

ifneq ($(TERRA_USE_PUC_LUA),)

LUA_VERSION=lua-5.1.5
LUA_TAR = $(LUA_VERSION).tar.gz
LUA_URL = https://www.lua.org/ftp/$(LUA_TAR)
LUA_DIR = build/$(LUA_VERSION)
LUA_LIB = $(LUA_DIR)/lib/liblua.a
LUA_INCLUDE = $(LUA_DIR)/include
LUA = $(LUA_DIR)/bin/lua
FLAGS += -DTERRA_USE_PUC_LUA

build/$(LUA_TAR):
	$(WGET) build/$(LUA_TAR) $(LUA_URL)

$(LUA_LIB): build/$(LUA_TAR)
	(cd build; tar -xf $(LUA_TAR))
	(cd $(LUA_DIR); make $(LUA_TARGET) && make local)

#rule for packaging lua code into bytecode, put into a header file via geninternalizedfiles.lua
build/%.bc:	src/%.lua $(PACKAGE_DEPS) $(LUA_LIB)
	$(LUA_DIR)/bin/luac -o $@ $<


else

# Add the following lines to Makefile.inc to switch to LuaJIT-2.1 beta releases
#LUAJIT_VERSION_BASE =2.1
#LUAJIT_VERSION_EXTRA =.0-beta2

LUAJIT_VERSION_BASE ?= 2.0
LUAJIT_VERSION_EXTRA ?= .4
LUAJIT_VERSION ?= LuaJIT-$(LUAJIT_VERSION_BASE)$(LUAJIT_VERSION_EXTRA)
LUAJIT_EXECUTABLE ?= luajit-$(LUAJIT_VERSION_BASE)$(LUAJIT_VERSION_EXTRA)
LUAJIT_URL ?= http://luajit.org/download/$(LUAJIT_VERSION).tar.gz
LUAJIT_TAR ?= $(LUAJIT_VERSION).tar.gz
LUAJIT_DIR ?= build/$(LUAJIT_VERSION)
LUA_LIB ?= $(LUAJIT_PREFIX)/lib/libluajit-5.1.a
LUA_INCLUDE ?= $(dir $(shell ls 2>/dev/null $(LUAJIT_PREFIX)/include/luajit-$(LUAJIT_VERSION_BASE)/lua.h || ls 2>/dev/null $(LUAJIT_PREFIX)/include/lua.h || echo $(LUAJIT_PREFIX)/include/luajit-$(LUAJIT_VERSION_BASE)/lua.h))
LUA ?= $(LUAJIT_PREFIX)/bin/$(LUAJIT_EXECUTABLE)

build/$(LUAJIT_TAR):
	$(WGET) build/$(LUAJIT_TAR) $(LUAJIT_URL)

build/lib/libluajit-5.1.a: build/$(LUAJIT_TAR)
	(cd build; tar -xf $(LUAJIT_TAR))
	(cd $(LUAJIT_DIR); make install PREFIX=$(realpath build) CC=$(CC) STATIC_CC="$(CC) $(PIC_FLAG)")

#rule for packaging lua code into bytecode, put into a header file via geninternalizedfiles.lua
build/%.bc:	src/%.lua $(PACKAGE_DEPS) $(LUA_LIB)
	$(LUA) -b -g $< $@
endif

###########################
# Rules for building Terra
###########################

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


AR = ar
LD = ld
FLAGS += -Wall -g $(PIC_FLAG)
LFLAGS = -g

# The -E flag is BSD-specific. It is supported (though undocumented)
# on certain newer versions of GNU Sed, but not all. Check for -E
# support and otherwise fall back to the GNU Sed flag -r.
SED_E = sed -E
ifeq ($(shell sed -E '' </dev/null >/dev/null 2>&1 && echo yes || echo no),no)
SED_E = sed -r
endif

FLAGS += -I build -I $(LUA_INCLUDE) -I release/include/terra  -I $(shell $(LLVM_CONFIG) --includedir) -I $(CLANG_PREFIX)/include

FLAGS += -D_GNU_SOURCE -D__STDC_CONSTANT_MACROS -D__STDC_FORMAT_MACROS -D__STDC_LIMIT_MACROS -O0 -fno-common -Wcast-qual
CPPFLAGS = -fno-rtti -Woverloaded-virtual -fvisibility-inlines-hidden

LLVM_VERSION_NUM=$(shell $(LLVM_CONFIG) --version | sed -e s/svn//)
LLVM_VERSION=$(shell echo $(LLVM_VERSION_NUM) | $(SED_E) 's/^([0-9]+)\.([0-9]+).*/\1\2/')
LLVMVERGT4 := $(shell expr $(LLVM_VERSION) \>= 40)

FLAGS += -DLLVM_VERSION=$(LLVM_VERSION)

#set TERRA_EXTERNAL_TERRALIB=1 to use the on-disk lua files like terralib.lua, useful for faster iteration when debugging terra itself.
ifneq ($(TERRA_EXTERNAL_TERRALIB),)
FLAGS += -DTERRA_EXTERNAL_TERRALIB="\"$(realpath src)/?.lua\""
endif

# customizable path locations for LuaRocks install
ifneq ($(TERRA_HOME),)
FLAGS += -DTERRA_HOME="\"$(TERRA_HOME)\""
endif

ifneq ($(LLVM_VERSION), 32)
CPPFLAGS += -std=c++11
endif


ifneq ($(findstring $(UNAME), Linux FreeBSD),)
DYNFLAGS = -shared $(PIC_FLAG)
WHOLE_ARCHIVE += -Wl,-export-dynamic -Wl,--whole-archive $(LIBRARY) -Wl,--no-whole-archive
else
DYNFLAGS = -undefined dynamic_lookup -dynamiclib -single_module $(PIC_FLAG) -install_name "@rpath/terra.so"
WHOLE_ARCHIVE =  -Wl,-force_load,$(1)
endif

LLVM_LIBRARY_FLAGS += $(LUA_LIB)
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

PACKAGE_DEPS += $(LUA_LIB)

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
LIBLUA = terralib.lua terralib_jit.lua terralib_puc.lua strict.lua cudalib.lua asdl.lua terralist.lua terrautil.lua luatypeannotation.lua

EXEOBJS = main.o linenoise.o

EMBEDDEDLUA = $(addprefix build/,$(LIBLUA:.lua=.bc))
GENERATEDHEADERS = $(EMBEDDEDLUA) build/clangpaths.h build/internalizedfiles.h

LUAHEADERS = lua.h lualib.h lauxlib.h luaconf.h

OBJS = $(LIBOBJS) $(EXEOBJS)

LIBRARY = release/lib/libterra.a
LIBRARY_NOLUA = release/lib/libterra_nolua.a
LIBRARY_NOLUA_NOLLVM = release/lib/libterra_nolua_nollvm.a
LIBRARY_VARIANTS = $(LIBRARY_NOLUA) $(LIBRARY_NOLUA_NOLLVM)
RELEASE_HEADERS = $(addprefix release/include/terra/,$(LUAHEADERS))

.PHONY:	all clean download purge test release install
all:	$(EXECUTABLE) $(DYNLIBRARY)

test:	all
	(cd tests; ./run)

variants:	$(LIBRARY_VARIANTS)

build/%.o:	src/%.cpp $(PACKAGE_DEPS)
	$(CXX) $(FLAGS) $(CPPFLAGS) $< -c -o $@

build/%.o:	src/%.c $(PACKAGE_DEPS)
	$(CC) $(FLAGS) $< -c -o $@

download: build/$(LUA_TAR)

build/$(LUA_TAR):
ifeq ($(UNAME), Darwin)
	curl $(LUA_URL) -o build/$(LUA_TAR)
else
	wget $(LUA_URL) -O build/$(LUA_TAR)
endif

build/lib/libluajit-5.1.a: build/$(LUA_TAR)
	(cd build; tar -xf $(LUA_TAR))
	(cd $(LUA_DIR); $(MAKE) install PREFIX=$(realpath build) CC=$(CC) STATIC_CC="$(CC) -fPIC")

release/include/terra/%.h:  $(LUA_INCLUDE)/%.h $(LUA_LIB) 
	cp $(LUA_INCLUDE)/$*.h $@
    
build/llvm_objects/llvm_list:    $(addprefix build/, $(LIBOBJS) $(EXEOBJS))
	mkdir -p build/llvm_objects/luajit
	$(CXX) -o /dev/null $(addprefix build/, $(LIBOBJS) $(EXEOBJS)) $(LLVM_LIBRARY_FLAGS) $(SUPPORT_LIBRARY_FLAGS) $(LFLAGS) -Wl,-t 2>&1 | egrep "lib(LLVM|clang)"  > build/llvm_objects/llvm_list
	# extract needed LLVM objects based on a dummy linker invocation
	< build/llvm_objects/llvm_list $(LUA) src/unpacklibraries.lua build/llvm_objects
	# include all luajit objects, since the entire lua interface is used in terra


build/lua_objects/lj_obj.o:    $(LUA_LIB)
	mkdir -p build/lua_objects
	cd build/lua_objects; ar x $(realpath $(LUA_LIB))

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

$(DYNLIBRARY):	$(LIBRARY_NOLUA)
	mkdir -p release/lualib
	$(CXX) $(DYNFLAGS) $(call WHOLE_ARCHIVE,$(LIBRARY_NOLUA)) $(SUPPORT_LIBRARY_FLAGS) -o $@

ifeq ($(TERRA_EXTERNAL_LUA),)
LUA_AND_TERRA=$(call WHOLE_ARCHIVE,$(LIBRARY))
EXECUTABLE_LIBRARY_DEPENDENCY=$(LIBRARY)
else
LUA_AND_TERRA=$(LUA_LIB) $(call WHOLE_ARCHIVE,$(LIBRARY_NOLUA))
EXECUTABLE_LIBRARY_DEPENDENCY=$(LIBRARY_NOLUA)
endif

$(EXECUTABLE):	$(addprefix build/, $(EXEOBJS)) $(EXECUTABLE_LIBRARY_DEPENDENCY)
	mkdir -p release/bin release/lib
	$(CXX) $(addprefix build/, $(EXEOBJS)) -o $@ $(LFLAGS) $(LUA_AND_TERRA) $(SUPPORT_LIBRARY_FLAGS) $(TERRA_RPATH_FLAGS)
	if [ ! -e terra  ]; then ln -s $(EXECUTABLE) terra; fi;

#run clang on a C file to extract the header search paths for this architecture
#genclangpaths.lua find the path arguments and formats them into a C file that is included by the cwrapper
#to configure the paths
build/clangpaths.h:	src/dummy.c $(PACKAGE_DEPS) src/genclangpaths.lua
	$(LUA) src/genclangpaths.lua $@ $(CLANG) $(CUDA_INCLUDES)

TERRA_LIBRARY_FILES=lib/std.t lib/parsing.t lib/terraffi.t
build/internalizedfiles.h:	$(PACKAGE_DEPS) src/geninternalizedfiles.lua $(TERRA_LIBRARY_FILES) $(EMBEDDEDLUA)
	$(LUA) src/geninternalizedfiles.lua POSIX $(CLANG_RESOURCE_DIRECTORY) $@

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

install: all
	cp -R release/bin/* $(INSTALL_BINARY_DIR)
	cp -R release/lib/* $(INSTALL_LIBRARY_DIR)
	cp -R release/share/* $(INSTALL_SHARE_DIR)
	cp -R release/include/* $(INSTALL_INCLUDE_DIR)
	cp -R release/lualib/* $(INSTALL_LUA_LIBRARY_DIR)

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
