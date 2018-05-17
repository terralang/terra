
# Edit these three paths to your 
# (1) LLVM install (should have bin/ include/ and lib/ directories)
# (2) LuaJIT 2.0.3 download directory (does not need to be built)
# (3) directory where you downloaded the Terra source
# all paths must be ABSOLUTE

!IFNDEF LLVM_DIR
LLVM_DIR=C:\Users\zdevito\LLVM
!ENDIF

!IFNDEF LLVM_VERSION
LLVM_VERSION=3.5.0
!ENDIF

!IFNDEF LLVM_VERSION_SHORT
LLVM_VERSION_SHORT=35
!ENDIF

!IFNDEF LUAJIT_DIR
LUAJIT_DIR=C:\Users\zdevito\LuaJIT-2.0.4
!ENDIF

!IFNDEF TERRA_DIR
TERRA_DIR=C:\Users\zdevito\terra
!ENDIF

!IFNDEF CUDA_DIR
CUDA_DIR=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v6.5
!ENDIF

SRC = $(TERRA_DIR)\src
BUILD = $(TERRA_DIR)\build


LIBS= LLVMAnalysis.lib LLVMAsmParser.lib LLVMAsmPrinter.lib LLVMBitReader.lib   \
      LLVMBitWriter.lib LLVMCodeGen.lib LLVMCore.lib LLVMDebugInfo.lib          \
      LLVMExecutionEngine.lib LLVMInstCombine.lib LLVMInstrumentation.lib       \
      LLVMInterpreter.lib LLVMipa.lib LLVMipo.lib LLVMIRReader.lib              \
      LLVMJIT.lib LLVMLineEditor.lib LLVMLinker.lib LLVMLTO.lib LLVMMC.lib      \
      LLVMMCAnalysis.lib LLVMMCDisassembler.lib LLVMMCJIT.lib                   \
      LLVMMCParser.lib LLVMObjCARCOpts.lib LLVMObject.lib LLVMOption.lib        \
      LLVMProfileData.lib LLVMRuntimeDyld.lib LLVMScalarOpts.lib                \
      LLVMSelectionDAG.lib LLVMSupport.lib LLVMTableGen.lib LLVMTarget.lib      \
      LLVMTransformUtils.lib LLVMVectorize.lib LLVMX86AsmParser.lib             \
      LLVMX86AsmPrinter.lib LLVMX86CodeGen.lib LLVMX86Desc.lib                  \
      LLVMX86Disassembler.lib LLVMX86Info.lib LLVMX86Utils.lib                  \
      clangAnalysis.lib clangARCMigrate.lib clangAST.lib clangASTMatchers.lib   \
      clangBasic.lib clangCodeGen.lib clangDriver.lib                           \
      clangDynamicASTMatchers.lib clangEdit.lib clangFormat.lib                 \
      clangFrontend.lib clangFrontendTool.lib clangIndex.lib clangLex.lib       \
      clangParse.lib clangRewrite.lib clangRewriteFrontend.lib clangSema.lib    \
      clangSerialization.lib clangStaticAnalyzerCheckers.lib                    \
      clangStaticAnalyzerCore.lib clangStaticAnalyzerFrontend.lib               \
      clangTooling.lib                                                          \
      $(LUAJIT_DIR)\src\lua51.lib Shlwapi.lib

LIBPATHS = /LIBPATH:"$(LLVM_DIR)\lib"

!IFNDEF CLANG_RESOURCE_DIRECTORY
CLANG_RESOURCE_DIRECTORY=$(LLVM_DIR)\lib\clang\$(LLVM_VERSION)
!ENDIF

TERRALIB_SRC = $(SRC)\lctype.cpp $(SRC)\llex.cpp $(SRC)\lobject.cpp $(SRC)\lparser.cpp $(SRC)\lstring.cpp $(SRC)\lzio.cpp $(SRC)\tcompiler.cpp $(SRC)\tcuda.cpp $(SRC)\tcwrapper.cpp $(SRC)\tdebug.cpp $(SRC)\terra.cpp $(SRC)\tinline.cpp $(SRC)\tkind.cpp $(SRC)\tllvmutil.cpp $(SRC)\tinternalizedfiles.cpp $(SRC)\treadnumber.c $(SRC)\lj_strscan.c
CPP=cl
LINK=link

LUAJIT = $(LUAJIT_DIR)\src\luajit.exe

CPPFLAGS = /MP8 /nologo /EHsc /w /MD /Zi /D_CRT_SECURE_NO_DEPRECATE /DNOMINMAX /DTERRA_LLVM_HEADERS_HAVE_NDEBUG \
           /I$(LUAJIT_DIR)\src /I$(SRC) /I$(BUILD) /I$(TERRA_DIR)\release\include\terra /I$(LLVM_DIR)\include /I$(TERRA_DIR)\msvc \
           /DLLVM_VERSION=$(LLVM_VERSION_SHORT) \
           /DTERRA_ENABLE_CUDA /I"$(CUDA_DIR)\include" /I"$(CUDA_DIR)\nvvm\include"

all:	$(TERRA_DIR)\release\bin\terra.exe

$(LUAJIT) $(TERRA_DIR)\release\include\terra\lua.h:	$(LUAJIT_DIR)\src\luajit.c
	cd $(LUAJIT_DIR)\src
	msvcbuild.bat
	copy lua.h $(TERRA_DIR)\release\include\terra
	copy lualib.h $(TERRA_DIR)\release\include\terra
	copy lauxlib.h $(TERRA_DIR)\release\include\terra
	copy luaconf.h $(TERRA_DIR)\release\include\terra

$(BUILD)\terralib.h $(BUILD)\strict.h $(BUILD)\cudalib.h:	$(SRC)\terralib.lua $(SRC)\strict.lua $(SRC)\cudalib.lua $(LUAJIT) $(TERRA_DIR)\release\include\terra\lua.h
	set LUA_PATH=$(LUAJIT_DIR)\src\?.lua
	$(LUAJIT) -bg $(SRC)\terralib.lua $(BUILD)\terralib.h
	$(LUAJIT) -bg $(SRC)\strict.lua $(BUILD)\strict.h
	$(LUAJIT) -bg $(SRC)\cudalib.lua $(BUILD)\cudalib.h
	$(LUAJIT) -bg $(SRC)\asdl.lua $(BUILD)\asdl.h

$(BUILD)\clangpaths.h:	$(LUAJIT) $(SRC)\genclangpaths.lua
	cd $(TERRA_DIR)
	$(LUAJIT) src\genclangpaths.lua build\clangpaths.h $(LLVM_DIR)\bin\clang -I "$(CUDA_DIR:\=/)/include"

$(BUILD)\internalizedfiles.h:	$(LUAJIT)  $(SRC)\geninternalizedfiles.lua
	cd $(TERRA_DIR)
	$(LUAJIT) src\geninternalizedfiles.lua  build\internalizedfiles.h $(CLANG_RESOURCE_DIRECTORY) "%.h$$" $(CLANG_RESOURCE_DIRECTORY) "%.modulemap$$" $(TERRA_DIR)\lib "%.t$$" 

EXPORTS = /EXPORT:terra_init /EXPORT:terra_initwithoptions /EXPORT:terra_load /EXPORT:terra_loadfile /EXPORT:terra_loadbuffer /EXPORT:terra_loadstring /EXPORT:terra_llvmshutdown

$(BUILD)\terra.obj:	$(BUILD)\clangpaths.h $(BUILD)\internalizedfiles.h $(BUILD)\terralib.h $(BUILD)\strict.h $(BUILD)\cudalib.h $(TERRALIB_SRC)
	cd $(BUILD)
	$(CPP) $(CPPFLAGS) /c $(TERRALIB_SRC)

$(TERRA_DIR)\release\bin\terra.dll: $(BUILD)\terra.obj
	if not exist $(TERRA_DIR)\release\bin mkdir $(TERRA_DIR)\release\bin
	if not exist $(TERRA_DIR)\release\lib mkdir $(TERRA_DIR)\release\lib
	cd $(TERRA_DIR)\release\bin
	$(LINK) /nologo /MACHINE:X64 /DLL /DEBUG /PDB:terralib.pdb /out:terra.dll /IMPLIB:terra.lib $(BUILD)/*.obj $(LIBS) $(LIBPATHS) $(EXPORTS)
	move terra.lib ..\lib\terra.lib

REDIST=$(VCINSTALLDIR)redist\x64\Microsoft.VC120.CRT

$(TERRA_DIR)\release\bin\terra.exe: $(TERRA_DIR)\release\bin\terra.dll $(SRC)\main.cpp
	cd $(TERRA_DIR)
	copy $(LUAJIT_DIR)\src\lua51.dll release\bin
	copy $(LUAJIT_DIR)\src\lua51.lib release\lib
	copy "$(REDIST)\msvcp120.dll" release\bin
	copy "$(REDIST)\msvcr120.dll" release\bin
	$(CPP) $(CPPFLAGS) /Fe:$@ $(SRC)\main.cpp $(TERRA_DIR)\msvc\ext\getopt.c $(TERRA_DIR)\msvc\ext\getopt_long.c $(TERRA_DIR)\release\lib\terra.lib $(LUAJIT_DIR)\src\lua51.lib

clean:
	del ..\build\*.obj ..\build\*.h ..\build\terra.lib ..\release\bin\terra.dll ..\release\lib\terra.lib ..\release\bin\terra.exe

.SUFFIXES:
