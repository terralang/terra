
# Edit these three paths to your 
# (1) LLVM install (should have bin/ include/ and lib/ directories)
# (2) LuaJIT 2.0.3 download directory (does not need to be built)
# (3) directory where you downloaded the Terra source
# all paths must be ABSOLUTE

LLVM_DIR=C:\Users\zdevito\LLVM
LUAJIT_DIR=C:\Users\zdevito\LuaJIT-2.0.3
TERRA_DIR=C:\Users\zdevito\terra
CUDA_DIR=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v6.5

SRC = $(TERRA_DIR)\src
BUILD = $(TERRA_DIR)\build


LIBS=      LLVMLTO.lib  LLVMObjCARCOpts.lib  LLVMLinker.lib  LLVMipo.lib  LLVMVectorize.lib \
           LLVMBitWriter.lib  LLVMIRReader.lib  LLVMAsmParser.lib  LLVMXCoreDisassembler.lib \
           LLVMXCoreCodeGen.lib  LLVMXCoreDesc.lib  LLVMXCoreInfo.lib  LLVMXCoreAsmPrinter.lib \
           LLVMSystemZDisassembler.lib  LLVMSystemZCodeGen.lib  LLVMSystemZAsmParser.lib  LLVMSystemZDesc.lib \
           LLVMSystemZInfo.lib  LLVMSystemZAsmPrinter.lib  LLVMSparcDisassembler.lib  LLVMSparcCodeGen.lib \
           LLVMSparcAsmParser.lib  LLVMSparcDesc.lib  LLVMSparcInfo.lib  LLVMSparcAsmPrinter.lib \
           LLVMR600CodeGen.lib  LLVMR600Desc.lib  LLVMR600Info.lib  LLVMR600AsmPrinter.lib \
           LLVMPowerPCDisassembler.lib  LLVMPowerPCCodeGen.lib  LLVMPowerPCAsmParser.lib  LLVMPowerPCDesc.lib \
           LLVMPowerPCInfo.lib  LLVMPowerPCAsmPrinter.lib  LLVMNVPTXCodeGen.lib  LLVMNVPTXDesc.lib \
           LLVMNVPTXInfo.lib  LLVMNVPTXAsmPrinter.lib  LLVMMSP430CodeGen.lib  LLVMMSP430Desc.lib \
           LLVMMSP430Info.lib  LLVMMSP430AsmPrinter.lib  LLVMMipsDisassembler.lib  LLVMMipsCodeGen.lib \
           LLVMMipsAsmParser.lib  LLVMMipsDesc.lib  LLVMMipsInfo.lib  LLVMMipsAsmPrinter.lib \
           LLVMHexagonCodeGen.lib  LLVMHexagonAsmPrinter.lib  LLVMHexagonDesc.lib  LLVMHexagonInfo.lib \
           LLVMCppBackendCodeGen.lib  LLVMCppBackendInfo.lib  LLVMARMDisassembler.lib  LLVMARMCodeGen.lib \
           LLVMARMAsmParser.lib  LLVMARMDesc.lib  LLVMARMInfo.lib  LLVMARMAsmPrinter.lib \
           LLVMAArch64Disassembler.lib  LLVMAArch64CodeGen.lib  LLVMAArch64AsmParser.lib  LLVMAArch64Desc.lib \
           LLVMAArch64Info.lib  LLVMAArch64AsmPrinter.lib  LLVMAArch64Utils.lib  LLVMTableGen.lib \
           LLVMDebugInfo.lib  LLVMOption.lib  LLVMX86Disassembler.lib  LLVMX86AsmParser.lib \
           LLVMX86CodeGen.lib  LLVMSelectionDAG.lib  LLVMAsmPrinter.lib  LLVMX86Desc.lib  LLVMX86Info.lib \
           LLVMX86AsmPrinter.lib  LLVMX86Utils.lib  LLVMJIT.lib  LLVMLineEditor.lib  LLVMMCAnalysis.lib \
           LLVMMCDisassembler.lib  LLVMInstrumentation.lib  LLVMInterpreter.lib  LLVMCodeGen.lib \
           LLVMScalarOpts.lib  LLVMInstCombine.lib  LLVMTransformUtils.lib  LLVMipa.lib  LLVMAnalysis.lib \
           LLVMProfileData.lib  LLVMMCJIT.lib  LLVMTarget.lib  LLVMRuntimeDyld.lib  LLVMObject.lib \
           LLVMMCParser.lib  LLVMBitReader.lib  LLVMExecutionEngine.lib  LLVMMC.lib  LLVMCore.lib \
           LLVMSupport.lib \
           clangTooling.lib clangAnalysis.lib clangARCMigrate.lib clangAST.lib clangASTMatchers.lib clangBasic.lib \
           clangCodeGen.lib clangDriver.lib clangEdit.lib clangFrontend.lib clangFrontendTool.lib clangLex.lib \
           clangParse.lib clangRewrite.lib clangRewriteFrontend.lib clangSema.lib clangSerialization.lib \
           clangStaticAnalyzerCheckers.lib clangStaticAnalyzerCore.lib clangStaticAnalyzerFrontend.lib \
           $(LUAJIT_DIR)\src\lua51.lib Shlwapi.lib

LIBPATHS = /LIBPATH:"$(LLVM_DIR)\lib"

CLANG_RESOURCE_DIRECTORY=$(LLVM_DIR)\lib\clang\3.5.0

TERRALIB_SRC = $(SRC)\lctype.cpp $(SRC)\llex.cpp $(SRC)\lobject.cpp $(SRC)\lparser.cpp $(SRC)\lstring.cpp $(SRC)\lzio.cpp $(SRC)\tcompiler.cpp $(SRC)\tcuda.cpp $(SRC)\tcwrapper.cpp $(SRC)\tdebug.cpp $(SRC)\terra.cpp $(SRC)\tinline.cpp $(SRC)\tkind.cpp $(SRC)\tllvmutil.cpp $(SRC)\treadnumber.c

CPP=cl
LINK=link

LUAJIT = $(LUAJIT_DIR)\src\luajit.exe

CPPFLAGS = /nologo /EHsc /w /MD /Zi /D_CRT_SECURE_NO_DEPRECATE /DNOMINMAX /DTERRA_LLVM_HEADERS_HAVE_NDEBUG \
           /I$(LUAJIT_DIR)\src /I$(SRC) /I$(BUILD) /I$(TERRA_DIR)\release\include /I$(LLVM_DIR)\include /I$(TERRA_DIR)\msvc \
           /DLLVM_VERSION=35 \
           /DTERRA_ENABLE_CUDA /I"$(CUDA_DIR)\include" /I"$(CUDA_DIR)\nvvm\include"

all:	$(TERRA_DIR)\release\terra.exe

$(LUAJIT):	$(LUAJIT_DIR)\src\luajit.c
	cd $(LUAJIT_DIR)\src
	msvcbuild.bat
	copy lua.h $(TERRA_DIR)\release\include
	copy lualib.h $(TERRA_DIR)\release\include
	copy lauxlib.h $(TERRA_DIR)\release\include
	copy luaconf.h $(TERRA_DIR)\release\include

$(BUILD)\terralib.h $(BUILD)\strict.h $(BUILD)\cudalib.h:	$(SRC)\terralib.lua $(SRC)\strict.lua $(SRC)\cudalib.lua $(LUAJIT)
	set LUA_PATH=$(LUAJIT_DIR)\src\?.lua
	$(LUAJIT) -bg $(SRC)\terralib.lua $(BUILD)\terralib.h
	$(LUAJIT) -bg $(SRC)\strict.lua $(BUILD)\strict.h
	$(LUAJIT) -bg $(SRC)\cudalib.lua $(BUILD)\cudalib.h

$(BUILD)\clangpaths.h:	$(LUAJIT) $(SRC)\genclangpaths.lua
	cd $(TERRA_DIR)
	$(LUAJIT) src\genclangpaths.lua build\clangpaths.h $(LLVM_DIR)\bin\clang -I "$(CUDA_DIR:\=/)/include"

EXPORTS = /EXPORT:terra_init /EXPORT:terra_initwithoptions /EXPORT:terra_load /EXPORT:terra_loadfile /EXPORT:terra_loadbuffer /EXPORT:terra_loadstring /EXPORT:terra_llvmshutdown

$(BUILD)\terra.obj:	$(BUILD)\clangpaths.h $(BUILD)\terralib.h $(BUILD)\strict.h $(BUILD)\cudalib.h $(TERRALIB_SRC)
	cd $(BUILD)
	$(CPP) $(CPPFLAGS) /c $(TERRALIB_SRC)

$(TERRA_DIR)\release\terra.dll: $(BUILD)\terra.obj
	cd $(TERRA_DIR)\release
	$(LINK) /nologo /MACHINE:X64 /DLL /out:terra.dll /IMPLIB:terra.lib $(BUILD)/*.obj $(LIBS) $(LIBPATHS) $(EXPORTS)

REDIST=$(VCINSTALLDIR)redist\x64\Microsoft.VC120.CRT

$(TERRA_DIR)\release\terra.exe: $(TERRA_DIR)\release\terra.dll $(SRC)\main.cpp
	cd $(TERRA_DIR)
	copy $(LUAJIT_DIR)\src\lua51.dll release
	copy $(LUAJIT_DIR)\src\lua51.lib release
	copy "$(REDIST)\msvcp120.dll" release
	copy "$(REDIST)\msvcr120.dll" release
	xcopy /E /I /Q /Y $(CLANG_RESOURCE_DIRECTORY) release\include\clang_resource
	$(CPP) $(CPPFLAGS) /Fe:$@ $(SRC)\main.cpp $(TERRA_DIR)\msvc\ext\getopt.c $(TERRA_DIR)\msvc\ext\getopt_long.c $(TERRA_DIR)\release\terra.lib $(LUAJIT_DIR)\src\lua51.lib

clean:
	del ..\build\*.obj ..\build\*.h ..\build\terra.lib ..\release\terra.exe ..\release\clang.exe
	rmdir /s ..\release\include\clang_resource 

.SUFFIXES: