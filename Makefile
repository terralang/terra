
# If the defaults for LLVM_CONFIG are not right for your installation
# create a Makefile.inc file and point LLVM_CONFIG at the llvm-config binary for your llvm distribution
# you may also need to reassign the TERRA_CXX and TERRA_CC compilers if they are not valid.
# If you want to enable cuda compiler support is enabled if the path specified by
# CUDA_HOME exists

-include Makefile.inc

LLVM_CONFIG ?= $(shell which llvm-config)

LLVM_PREFIX = $(shell $(LLVM_CONFIG) --prefix)

#if clang is not installed in the same prefix as llvm
#then use the clang in the caller's path
ifeq ($(wildcard $(LLVM_PREFIX)/bin/clang),)
CLANG_PREFIX ?= $(dir $(shell which clang))..
else
CLANG_PREFIX ?= $(LLVM_PREFIX)
endif

#path to the clang binary, must be specifically clang
CLANG ?= $(CLANG_PREFIX)/bin/clang

#path to the compiler you want to use to compile libterra
#can be any c/c++ compiler
TERRA_CXX ?= $(CLANG)++
TERRA_CC  ?= $(CLANG)
TERRA_LINK ?= $(CLANG)++

CUDA_HOME ?= /usr/local/cuda
ENABLE_CUDA ?= $(shell test -e /usr/local/cuda && echo 1 || echo 0)

CXX := $(TERRA_CXX)
CC := $(TERRA_CC)

.SUFFIXES:
.SECONDARY:
UNAME := $(shell uname)


AR = ar
LD = ld
FLAGS = -Wall -g -fPIC
LFLAGS = -g

#luajit will be downloaded automatically (it's much smaller than llvm)
LUAJIT_VERSION=LuaJIT-2.0.3
LUAJIT_URL=http://luajit.org/download/$(LUAJIT_VERSION).tar.gz
LUAJIT_TAR=$(LUAJIT_VERSION).tar.gz
LUAJIT_DIR=build/$(LUAJIT_VERSION)

LUAJIT_LIB=build/$(LUAJIT_VERSION)/src/libluajit.a

FLAGS += -I build -I release/include -I $(LUAJIT_DIR)/src -I $(shell $(LLVM_CONFIG) --includedir) -I $(CLANG_PREFIX)/include

FLAGS += -D_GNU_SOURCE -D__STDC_CONSTANT_MACROS -D__STDC_FORMAT_MACROS -D__STDC_LIMIT_MACROS -O0 -fno-rtti -fno-common -Woverloaded-virtual -Wcast-qual -fvisibility-inlines-hidden

LLVM_VERSION_NUM=$(shell $(LLVM_CONFIG) --version | sed -e s/svn//)
LLVM_VERSION=$(shell echo $(LLVM_VERSION_NUM) | sed -E 's/^([0-9]+)\.([0-9]+).*/\1\2/')

FLAGS += -DLLVM_VERSION=$(LLVM_VERSION)
ifneq ($(LLVM_VERSION), 32)
CPPFLAGS = -std=c++11 -Wno-c++11-narrowing
endif


ifeq ($(UNAME), Linux)
DYNFLAGS = -shared -fPIC
SO_FLAGS += -Wl,-export-dynamic -Wl,--whole-archive $(LUAJIT_LIB) $(LIBRARY) -Wl,--no-whole-archive
else
DYNFLAGS = -dynamiclib -single_module -fPIC -install_name "@rpath/libterra.so"
SO_FLAGS += -Wl,-force_load,$(LUAJIT_LIB),-force_load,$(LIBRARY)
endif

SO_FLAGS += $(shell $(LLVM_CONFIG) --ldflags) -L$(CLANG_PREFIX)/lib
SO_FLAGS  += -lclangFrontend -lclangDriver \
           -lclangSerialization -lclangCodeGen -lclangParse -lclangSema \
           -lclangAnalysis \
           -lclangEdit -lclangAST -lclangLex -lclangBasic
ifneq ($(LLVM_VERSION), 35)
SO_FLAGS += -lclangRewriteCore
endif
SO_FLAGS += $(shell $(LLVM_CONFIG) --libs)
# llvm sometimes requires ncurses and libz, check if they have the symbols, and add them if they do
ifeq ($(shell nm $(LLVM_PREFIX)/lib/libLLVMSupport.a | grep setupterm 2>&1 >/dev/null; echo $$?), 0)
    SO_FLAGS += -lcurses 
endif
ifeq ($(shell nm $(LLVM_PREFIX)/lib/libLLVMSupport.a | grep compress2 2>&1 >/dev/null; echo $$?), 0)
    SO_FLAGS += -lz
endif

ifeq ($(UNAME), Linux)
SO_FLAGS += -ldl -pthread
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

ifeq (,$(findstring Asserts, $(shell $(LLVM_CONFIG) --build-mode)))
FLAGS += -DTERRA_LLVM_HEADERS_HAVE_NDEBUG
endif

LIBOBJS = tkind.o tcompiler.o tllvmutil.o tcwrapper.o tinline.o terra.o lparser.o lstring.o lobject.o lzio.o llex.o lctype.o treadnumber.o tcuda.o tdebug.o
LIBLUA = terralib.lua strict.lua cudalib.lua

EXEOBJS = main.o linenoise.o

EMBEDDEDLUA = $(addprefix build/,$(LIBLUA:.lua=.h))
GENERATEDHEADERS = $(EMBEDDEDLUA) build/clangpaths.h

LUAHEADERS = lua.h lualib.h lauxlib.h luaconf.h

OBJS = $(LIBOBJS) $(EXEOBJS)

EXECUTABLE = release/terra
LIBRARY = build/libterra.a
DYNLIBRARY = release/libterra.so

BIN2C = build/bin2c

#put any install-specific stuff in here
-include Makefile.inc

.PHONY:	all clean purge test release
all:	$(EXECUTABLE) $(DYNLIBRARY)

test:	$(EXECUTABLE)
	(cd tests; ./run)

build/%.o:	src/%.cpp $(PACKAGE_DEPS)
	$(CXX) $(FLAGS) $(CPPFLAGS) $< -c -o $@

build/%.o:	src/%.c $(PACKAGE_DEPS)
	$(CC) $(FLAGS) $< -c -o $@

build/$(LUAJIT_TAR):
ifeq ($(UNAME), Darwin)
	curl $(LUAJIT_URL) -o build/$(LUAJIT_TAR)
else
	wget $(LUAJIT_URL) -O build/$(LUAJIT_TAR)
endif

$(LUAJIT_LIB): build/$(LUAJIT_TAR)
	(cd build; tar -xf $(LUAJIT_TAR))
	(cd $(LUAJIT_DIR); make CC=$(CC) STATIC_CC="$(CC) -fPIC")
	cp $(addprefix $(LUAJIT_DIR)/src/,$(LUAHEADERS)) release/include
	
$(LIBRARY):	$(addprefix build/, $(LIBOBJS))
	rm -f $(LIBRARY)
	$(AR) -cq $@ $^

$(DYNLIBRARY):	$(LIBRARY)
	$(TERRA_LINK) $(DYNFLAGS) -o $@ $(SO_FLAGS)  

$(EXECUTABLE):	$(addprefix build/, $(EXEOBJS)) $(LIBRARY)
	cp -r $(CLANG_RESOURCE_DIRECTORY) release/include/clang_resource
	$(TERRA_LINK) $(addprefix build/, $(EXEOBJS)) -o $@ $(LFLAGS) $(SO_FLAGS)
	if [ ! -e terra  ]; then ln -s $(EXECUTABLE) terra; fi;

$(BIN2C):	src/bin2c.c
	$(CC) -O3 -o $@ $<


#rule for packaging lua code into a header file
build/%.h:	src/%.lua $(PACKAGE_DEPS)
	LUA_PATH=$(LUAJIT_DIR)/src/?.lua $(LUAJIT_DIR)/src/luajit -bg $< $@

#run clang on a C file to extract the header search paths for this architecture
#genclangpaths.lua find the path arguments and formats them into a C file that is included by the cwrapper
#to configure the paths	
build/clangpaths.h:	src/dummy.c $(PACKAGE_DEPS) src/genclangpaths.lua
	$(LUAJIT_DIR)/src/luajit src/genclangpaths.lua $@ $(CLANG) $(CUDA_INCLUDES)

clean:
	rm -rf build/*.o build/*.d $(GENERATEDHEADERS)
	rm -rf $(EXECUTABLE) terra $(LIBRARY) $(DYNLIBRARY) release/include/clang_resource

purge:	clean
	rm -rf build/* $(addprefix release/include/,$(LUAHEADERS))

RELEASE_NAME := terra-`uname | sed -e s/Darwin/OSX/ | sed -e s/CYGWIN.*/Windows/`-`uname -m`-`git rev-parse --short HEAD`
release:
	for i in `git ls-tree HEAD -r tests --name-only`; do mkdir -p release/`dirname $$i`; cp $$i release/$$i; done;
	mv release $(RELEASE_NAME)
	zip -q -r $(RELEASE_NAME).zip $(RELEASE_NAME)
	mv $(RELEASE_NAME) release
    
# dependency rules
DEPENDENCIES = $(patsubst %.o,build/%.d,$(OBJS))
build/%.d:	src/%.cpp $(PACKAGE_DEPS) $(GENERATEDHEADERS)
	@$(CXX) $(FLAGS) $(CPPFLAGS) -w -MM -MT '$@ $(@:.d=.o)' $< -o $@
build/%.d:	src/%.c $(PACKAGE_DEPS) $(GENERATEDHEADERS)
	@$(CC) $(FLAGS) -w -MM -MT '$@ $(@:.d=.o)' $< -o $@

#if we are cleaning, then don't include dependencies (which would require the header files are built)	
ifeq ($(findstring $(MAKECMDGOALS),purge clean release),)
-include $(DEPENDENCIES)
endif
