
# If the defaults for LLVM_CONFIG are not right for your installation
# create a Makefile.inc file and point LLVM_CONFIG at the llvm-config binary for your llvm distribution
# you may also need to reassign the TERRA_CXX and TERRA_CC compilers if they are not valid.
# If you want to enable cuda compiler support set ENABLE_CUDA to 1 in your Makefile.inc
# CUDA_HOME is your cuda installation

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

CUDA_HOME ?= /usr/local/cuda


CXX := $(TERRA_CXX)
CC := $(TERRA_CC)

.SUFFIXES:
.SECONDARY:
UNAME := $(shell uname)


AR = ar
LD = ld
FLAGS = -g $(INCLUDE_PATH) -fPIC
LFLAGS = -g

#luajit will be downloaded automatically (it's much smaller than llvm)
LUAJIT_VERSION=LuaJIT-2.0.1
LUAJIT_URL=http://luajit.org/download/$(LUAJIT_VERSION).tar.gz
LUAJIT_TAR=$(LUAJIT_VERSION).tar.gz
LUAJIT_DIR=build/$(LUAJIT_VERSION)

LUAJIT_LIB=build/$(LUAJIT_VERSION)/src/libluajit.a

LFLAGS += -Lbuild -lluajit
INCLUDE_PATH += -I $(LUAJIT_DIR)/src -I $(shell $(LLVM_CONFIG) --includedir) -I $(CLANG_PREFIX)/include

FLAGS += -D_GNU_SOURCE -D__STDC_CONSTANT_MACROS -D__STDC_FORMAT_MACROS -D__STDC_LIMIT_MACROS -O0  -fno-exceptions -fno-rtti -fno-common -Woverloaded-virtual -Wcast-qual -fvisibility-inlines-hidden


LLVM_VERSION_NUM=$(shell $(LLVM_CONFIG) --version | sed -e s/svn//)
LLVM_VERSION=LLVM_$(shell echo $(LLVM_VERSION_NUM) | sed -e s/\\./_/)

FLAGS += -D$(LLVM_VERSION)

# LLVM LIBS (STATIC, slow to link against but built by default)
SO_FLAGS += -L$(shell $(LLVM_CONFIG) --libdir) -L$(CLANG_PREFIX)/lib

# CLANG LIBS
SO_FLAGS  += -lclangFrontend -lclangDriver \
           -lclangSerialization -lclangCodeGen -lclangParse -lclangSema \
           -lclangAnalysis \
           -lclangEdit -lclangAST -lclangLex -lclangBasic
           #-lclangStaticAnalyzerFrontend -lclangStaticAnalyzerCheckers \
           #-lclangStaticAnalyzerCore \
           #-lclangFrontendTool \
           #-lclangARCMigrate
           
LLVM_FLAGS_MANUAL += \
-lLLVMAsmParser \
-lLLVMInstrumentation \
-lLLVMLinker \
-lLLVMArchive \
-lLLVMBitReader \
-lLLVMDebugInfo \
-lLLVMJIT \
-lLLVMipo \
-lLLVMVectorize \
-lLLVMBitWriter \
-lLLVMTableGen \
-lLLVMHexagonCodeGen \
-lLLVMHexagonDesc \
-lLLVMHexagonInfo \
-lLLVMHexagonAsmPrinter \
-lLLVMPTXCodeGen \
-lLLVMPTXDesc \
-lLLVMPTXInfo \
-lLLVMPTXAsmPrinter \
-lLLVMMBlazeAsmParser \
-lLLVMMBlazeDisassembler \
-lLLVMMBlazeCodeGen \
-lLLVMMBlazeDesc \
-lLLVMMBlazeAsmPrinter \
-lLLVMMBlazeInfo \
-lLLVMCppBackendCodeGen \
-lLLVMCppBackendInfo \
-lLLVMMSP430CodeGen \
-lLLVMMSP430Desc \
-lLLVMMSP430AsmPrinter \
-lLLVMMSP430Info \
-lLLVMXCoreCodeGen \
-lLLVMXCoreDesc \
-lLLVMXCoreInfo \
-lLLVMCellSPUCodeGen \
-lLLVMCellSPUDesc \
-lLLVMCellSPUInfo \
-lLLVMMipsDisassembler \
-lLLVMMipsAsmParser \
-lLLVMMipsCodeGen \
-lLLVMMipsDesc \
-lLLVMMipsInfo \
-lLLVMMipsAsmPrinter \
-lLLVMARMDisassembler \
-lLLVMARMAsmParser \
-lLLVMARMCodeGen \
-lLLVMARMDesc \
-lLLVMARMInfo \
-lLLVMARMAsmPrinter \
-lLLVMPowerPCCodeGen \
-lLLVMPowerPCDesc \
-lLLVMPowerPCInfo \
-lLLVMPowerPCAsmPrinter \
-lLLVMSparcCodeGen \
-lLLVMSparcDesc \
-lLLVMSparcInfo \
-lLLVMX86Disassembler \
-lLLVMX86AsmParser \
-lLLVMX86CodeGen \
-lLLVMSelectionDAG \
-lLLVMAsmPrinter \
-lLLVMX86Desc \
-lLLVMX86Info \
-lLLVMX86AsmPrinter \
-lLLVMX86Utils \
-lLLVMMCDisassembler \
-lLLVMMCParser \
-lLLVMInterpreter \
-lLLVMCodeGen \
-lLLVMScalarOpts \
-lLLVMInstCombine \
-lLLVMTransformUtils \
-lLLVMipa \
-lLLVMAnalysis \
-lLLVMMCJIT \
-lLLVMRuntimeDyld \
-lLLVMExecutionEngine \
-lLLVMTarget \
-lLLVMMC \
-lLLVMObject \
-lLLVMCore \
-lLLVMSupport


ifeq ($(LLVM_VERSION), LLVM_3_1)
SO_FLAGS += $(LLVM_FLAGS_MANUAL) -lclangRewrite
else
SO_FLAGS += $(shell $(LLVM_CONFIG) --libs) -lclangRewriteCore
endif

# LLVM LIBS (DYNAMIC, these are faster to link against, but are not built by default)
# LFLAGS += -lLLVM-3.1

ifeq ($(UNAME), Linux)
LFLAGS += -ldl -pthread -Wl,-export-dynamic 
DYNFLAGS = -shared -fPIC -Wl,-export-dynamic -ldl -pthread
else
DYNFLAGS = -dynamiclib -single_module -undefined dynamic_lookup -fPIC
endif

PACKAGE_DEPS += $(LUAJIT_LIB)

INCLUDE_PATH += -I build

#makes luajit happy on osx 10.6 (otherwise luaL_newstate returns NULL)
ifeq ($(UNAME), Darwin)
LFLAGS += -pagezero_size 10000 -image_base 100000000 
endif

#so header include paths can be correctly configured on linux
FLAGS += -DTERRA_CLANG_RESOURCE_DIRECTORY="\"$(CLANG_PREFIX)/lib/clang/$(LLVM_VERSION_NUM)/include\""

ifdef ENABLE_CUDA
FLAGS += -DTERRA_ENABLE_CUDA -I $(CUDA_HOME)/include
SO_FLAGS += -L$(CUDA_HOME)/lib64 -lcuda -lcudart -Wl,-rpath,$(CUDA_HOME)/lib64
endif

LIBOBJS = tkind.o tcompiler.o tllvmutil.o tcwrapper.o tinline.o terra.o lparser.o lstring.o lobject.o lzio.o llex.o lctype.o treadnumber.o tcuda.o
LIBLUA = terralib.lua strict.lua cudalib.lua

EXEOBJS = main.o linenoise.o

LUAHEADERS = $(addprefix build/,$(LIBLUA:.lua=.h))
GENERATEDHEADERS = $(LUAHEADERS) build/clangpaths.h

OBJS = $(LIBOBJS) $(EXEOBJS)

EXECUTABLE = terra
LIBRARY = build/libterra.a
DYNLIBRARY = build/libterra.so

BIN2C = build/bin2c

#put any install-specific stuff in here
-include Makefile.inc

.PHONY:	all clean purge test package
all:	$(EXECUTABLE) $(DYNLIBRARY)

test:	$(EXECUTABLE)
	(cd tests; ./run)

build/%.o:	src/%.cpp $(PACKAGE_DEPS)
	$(CXX) $(FLAGS) $< -c -o $@

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
	(cd $(LUAJIT_DIR); make CC=$(CC))
	cp $(LUAJIT_DIR)/src/libluajit.a build/libluajit.a
	
$(LIBRARY):	$(addprefix build/, $(LIBOBJS))
	rm -f $(LIBRARY)
	$(AR) -cq $@ $^

$(DYNLIBRARY):	$(addprefix build/, $(LIBOBJS))
	$(CXX) $(DYNFLAGS) $^ -o $@ $(SO_FLAGS)  

$(EXECUTABLE):	$(addprefix build/, $(EXEOBJS)) $(LIBRARY)
	$(CXX) $^ -o $@ $(LFLAGS) $(SO_FLAGS)

$(BIN2C):	src/bin2c.c
	$(CC) -O3 -o $@ $<


#rule for packaging lua code into a header file
build/%.h:	src/%.lua $(PACKAGE_DEPS)
	LUA_PATH=$(LUAJIT_DIR)/src/?.lua $(LUAJIT_DIR)/src/luajit -bg $< $@

#run clang on a C file to extract the header search paths for this architecture
#genclangpaths.lua find the path arguments and formats them into a C file that is included by the cwrapper
#to configure the paths	
build/clangpaths.h:	src/dummy.c $(PACKAGE_DEPS) src/genclangpaths.lua
	$(LUAJIT_DIR)/src/luajit src/genclangpaths.lua $@ $(CLANG) $(FLAGS)

clean:
	rm -rf build/*.o build/*.d $(GENERATEDHEADERS)
	rm -rf $(EXECUTABLE) $(LIBRARY)

purge:	clean
	rm -rf build/*
 
package:
	git archive --prefix=terra/ HEAD | bzip2 > terra-`git rev-parse --short HEAD`.tar.bz2
	
# dependency rules
DEPENDENCIES = $(patsubst %.o,build/%.d,$(OBJS))
build/%.d:	src/%.cpp $(PACKAGE_DEPS) $(GENERATEDHEADERS)
	@g++ $(FLAGS) -w -MM -MT '$@ $(@:.d=.o)' $< -o $@
build/%.d:	src/%.c $(PACKAGE_DEPS) $(GENERATEDHEADERS)
	@gcc $(FLAGS) -w -MM -MT '$@ $(@:.d=.o)' $< -o $@

#if we are cleaning, then don't include dependencies (which would require the header files are built)	
ifeq ($(findstring $(MAKECMDGOALS),purge clean),)
-include $(DEPENDENCIES)
endif
