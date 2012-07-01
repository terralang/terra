
.SUFFIXES:
UNAME := $(shell uname)

CXX = /usr/local/bin/clang++
CC = /usr/local/bin/clang
AR = ar
FLAGS = -g $(INCLUDE_PATH)
LFLAGS = -g

#luajit will be downloaded automatically (it's much smaller than llvm)
LUAJIT_VERSION=LuaJIT-2.0.0-beta10
LUAJIT_URL=http://luajit.org/download/$(LUAJIT_VERSION).tar.gz
LUAJIT_TAR=$(LUAJIT_VERSION).tar.gz
LUAJIT_DIR=build/$(LUAJIT_VERSION)

LUAJIT_LIB=build/$(LUAJIT_VERSION)/src/libluajit.a

LFLAGS += -Lbuild -lluajit -lterra
INCLUDE_PATH += -I$(LUAJIT_DIR)/src

# point LLVM_CONFIG at the llvm-config binary for your llvm distribution
#LLVM_CONFIG=$(shell which llvm-config)

LLVM_CONFIG=/usr/local/bin/llvm-config
FLAGS += -I/usr/local/include -D_GNU_SOURCE -D__STDC_CONSTANT_MACROS -D__STDC_FORMAT_MACROS -D__STDC_LIMIT_MACROS -O0  -fno-exceptions -fno-rtti -fno-common -Woverloaded-virtual -Wcast-qual -fvisibility-inlines-hidden


# LLVM LIBS (STATIC, slow to link against but built by default)
LFLAGS += $(shell $(LLVM_CONFIG) --ldflags --libs) -lLLVMLinker
# CLANG LIBS
LFLAGS  += -lclangFrontend -lclangDriver \
           -lclangSerialization -lclangCodeGen -lclangParse -lclangSema \
           -lclangAnalysis -lclangRewrite \
           -lclangEdit -lclangAST -lclangLex -lclangBasic
           #-lclangStaticAnalyzerFrontend -lclangStaticAnalyzerCheckers \
           #-lclangStaticAnalyzerCore \
           #-lclangFrontendTool \
           #-lclangARCMigrate

# LLVM LIBS (DYNAMIC, these are faster to link against, but are not built by default)
# LFLAGS += -lLLVM-3.1

PACKAGE_DEPS += $(LUAJIT_LIB)

INCLUDE_PATH += -Ibuild

#makes luajit happy on osx 10.6 (otherwise luaL_newstate returns NULL)
LFLAGS += -pagezero_size 10000 -image_base 100000000 

LIBSRC = tcwrapper.cpp tkind.cpp tcompiler.cpp terra.cpp lparser.cpp lstring.cpp main.cpp lobject.cpp lzio.cpp llex.cpp lctype.cpp linenoise.cpp
EXESRC = main.cpp linenoise.cpp

LIBOBJS = $(LIBSRC:.cpp=.o)
EXEOBJS = $(EXESRC:.cpp=.o)

OBJS = $(LIBOBJS) $(EXEOBJS)
SRC = $(LIBSRC) $(EXESRC)

EXECUTABLE = terra
LIBRARY = build/libterra.a

BIN2C = build/bin2c

.PHONY:	all clean purge test docs package
all:	$(EXECUTABLE)

test:	$(EXECUTABLE)
	(cd tests; ./run)

build/%.o:	src/%.cpp $(PACKAGE_DEPS) build/llvmheaders.h.pch
	$(CXX) $(FLAGS) -include-pch build/llvmheaders.h.pch $< -c -o $@

build/llvmheaders.h.pch:	src/llvmheaders.h
	$(CXX) $(FLAGS) -x c++-header $< -o $@ 

build/$(LUAJIT_TAR):
ifeq ($(UNAME), Darwin)
	curl $(LUAJIT_URL) -o build/$(LUAJIT_TAR)
else
	wget $(LUAJIT_URL) -O build/$(LUAJIT_TAR)
endif

$(LUAJIT_LIB): build/$(LUAJIT_TAR)
	(cd build; tar -xf $(LUAJIT_TAR))
	(cd $(LUAJIT_DIR); make)
	cp $(LUAJIT_DIR)/src/libluajit.a build/libluajit.a
	ln -s $(LUAJIT_VERSION)/lib build/jit

$(LIBRARY):	$(addprefix build/, $(LIBOBJS))
	rm -f $(LIBRARY)
	$(AR) -cq $@ $^

$(EXECUTABLE):	$(addprefix build/, $(EXEOBJS)) $(LIBRARY)
	$(CXX) $^ -o $@ $(LFLAGS)

$(BIN2C):	src/bin2c.c
	$(CC) -O3 -o $@ $<

build/terralib.h:	src/terralib.lua $(PACKAGE_DEPS)
	LUA_PATH=build/?.lua $(LUAJIT_DIR)/src/luajit -bg src/terralib.lua build/terralib.h


clean:
	rm -rf build/*.o build/*.d build/terralib.h build/llvmheaders.h.pch
	rm -rf $(EXECUTABLE) $(LIBRARY)

purge:	clean
	rm -rf build/*

docs:	
	make -C docs
 
package:
	git archive HEAD | bzip2 > terra.tar.bz2
	
# dependency rules
DEPENDENCIES = $(patsubst %.o,build/%.d,$(OBJS))
build/%.d:	src/%.cpp $(PACKAGE_DEPS) build/terralib.h
	@g++ $(FLAGS)  -MM -MT '$@ $(@:.d=.o)' $< -o $@
	
-include $(DEPENDENCIES)
