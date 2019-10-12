
# Edit these three paths to your 
# (1) LLVM install (should have bin/ include/ and lib/ directories)
# (2) LuaJIT 2.0.5 download directory (does not need to be built)
# (3) directory where you downloaded the Terra source
# all paths must be ABSOLUTE

!IFNDEF LLVM_DIR
LLVM_DIR=D:\Projects\llvm-6.0.1.src\build\install
!ENDIF

!IFNDEF LLVM_VERSION
LLVM_VERSION=6.0.1
!ENDIF

!IFNDEF LLVM_VERSION_SHORT
LLVM_VERSION_SHORT=60
!ENDIF

!IFNDEF LUAJIT_DIR
LUAJIT_DIR=D:\Projects\LuaJIT-2.0.5
!ENDIF

!IFNDEF TERRA_DIR
TERRA_DIR=D:\Projects\terra
!ENDIF

!IFNDEF TERRA_VERSION
TERRA_VERSION=unknown
!ENDIF

# Set this if you want to enable CUDA.
# CUDA_DIR=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v9.2
!IFDEF CUDA_DIR
CUDA_INCLUDES=/DTERRA_ENABLE_CUDA /I"$(CUDA_DIR)\include" /I"$(CUDA_DIR)\nvvm\include"
CUDA_DIR_INCLUDE=-I "$(CUDA_DIR:\=/)/include"
!ELSE
CUDA_INCLUDES=
CUDA_DIR_INCLUDE=
!ENDIF

SRC = $(TERRA_DIR)\src
BUILD = $(TERRA_DIR)\build

!IFNDEF LIBS
#Ideally, generate the clang/llvm lib list by reading all libs in the llvm/lib dir
!IF $(LLVM_VERSION_SHORT)==70
LIBS= clangAnalysis.lib clangARCMigrate.lib clangAST.lib clangASTMatchers.lib clangBasic.lib clangCodeGen.lib clangCrossTU.lib clangDriver.lib clangDynamicASTMatchers.lib clangEdit.lib clangFormat.lib clangFrontend.lib clangFrontendTool.lib clangHandleCXX.lib clangHandleLLVM.lib clangIndex.lib clangLex.lib clangParse.lib clangRewrite.lib clangRewriteFrontend.lib clangSema.lib clangSerialization.lib clangStaticAnalyzerCheckers.lib clangStaticAnalyzerCore.lib clangStaticAnalyzerFrontend.lib clangTooling.lib clangToolingASTDiff.lib clangToolingCore.lib clangToolingInclusions.lib clangToolingRefactor.lib libclang.lib LLVMAggressiveInstCombine.lib LLVMAnalysis.lib LLVMAsmParser.lib LLVMAsmPrinter.lib LLVMBinaryFormat.lib LLVMBitReader.lib LLVMBitWriter.lib LLVMCodeGen.lib LLVMCore.lib LLVMCoroutines.lib LLVMCoverage.lib LLVMDebugInfoCodeView.lib LLVMDebugInfoDWARF.lib LLVMDebugInfoMSF.lib LLVMDebugInfoPDB.lib LLVMDemangle.lib LLVMDlltoolDriver.lib LLVMExecutionEngine.lib LLVMFuzzMutate.lib LLVMGlobalISel.lib LLVMInstCombine.lib LLVMInstrumentation.lib LLVMInterpreter.lib LLVMipo.lib LLVMIRReader.lib LLVMLibDriver.lib LLVMLineEditor.lib LLVMLinker.lib LLVMLTO.lib LLVMMC.lib LLVMMCDisassembler.lib LLVMMCJIT.lib LLVMMCParser.lib LLVMMIRParser.lib LLVMNVPTXAsmPrinter.lib LLVMNVPTXCodeGen.lib LLVMNVPTXDesc.lib LLVMNVPTXInfo.lib LLVMObjCARCOpts.lib LLVMObject.lib LLVMObjectYAML.lib LLVMOption.lib LLVMOrcJIT.lib LLVMPasses.lib LLVMProfileData.lib LLVMRuntimeDyld.lib LLVMScalarOpts.lib LLVMSelectionDAG.lib LLVMSupport.lib LLVMSymbolize.lib LLVMTableGen.lib LLVMTarget.lib LLVMTransformUtils.lib LLVMVectorize.lib LLVMWindowsManifest.lib LLVMX86AsmParser.lib LLVMX86AsmPrinter.lib LLVMX86CodeGen.lib LLVMX86Desc.lib LLVMX86Disassembler.lib LLVMX86Info.lib LLVMX86Utils.lib LLVMXRay.lib \
      "$(LUAJIT_DIR)\src\lua51.lib" Shlwapi.lib dbghelp.lib Version.lib
!ELSE IF $(LLVM_VERSION_SHORT)==60
LIBS= clangAnalysis.lib clangARCMigrate.lib clangAST.lib clangASTMatchers.lib clangBasic.lib clangCodeGen.lib clangCrossTU.lib clangDriver.lib clangDynamicASTMatchers.lib clangEdit.lib clangFormat.lib clangFrontend.lib clangFrontendTool.lib clangHandleCXX.lib clangIndex.lib clangLex.lib clangParse.lib clangRewrite.lib clangRewriteFrontend.lib clangSema.lib clangSerialization.lib clangStaticAnalyzerCheckers.lib clangStaticAnalyzerCore.lib clangStaticAnalyzerFrontend.lib clangTooling.lib clangToolingASTDiff.lib clangToolingCore.lib clangToolingRefactor.lib libclang.lib LLVMAnalysis.lib LLVMAsmParser.lib LLVMAsmPrinter.lib LLVMBinaryFormat.lib LLVMBitReader.lib LLVMBitWriter.lib LLVMCodeGen.lib LLVMCore.lib LLVMCoroutines.lib LLVMCoverage.lib LLVMDebugInfoCodeView.lib LLVMDebugInfoDWARF.lib LLVMDebugInfoMSF.lib LLVMDebugInfoPDB.lib LLVMDemangle.lib LLVMDlltoolDriver.lib LLVMExecutionEngine.lib LLVMFuzzMutate.lib LLVMGlobalISel.lib LLVMInstCombine.lib LLVMInstrumentation.lib LLVMInterpreter.lib LLVMipo.lib LLVMIRReader.lib LLVMLibDriver.lib LLVMLineEditor.lib LLVMLinker.lib LLVMLTO.lib LLVMMC.lib LLVMMCDisassembler.lib LLVMMCJIT.lib LLVMMCParser.lib LLVMMIRParser.lib LLVMNVPTXAsmPrinter.lib LLVMNVPTXCodeGen.lib LLVMNVPTXDesc.lib LLVMNVPTXInfo.lib LLVMObjCARCOpts.lib LLVMObject.lib LLVMObjectYAML.lib LLVMOption.lib LLVMOrcJIT.lib LLVMPasses.lib LLVMProfileData.lib LLVMRuntimeDyld.lib LLVMScalarOpts.lib LLVMSelectionDAG.lib LLVMSupport.lib LLVMSymbolize.lib LLVMTableGen.lib LLVMTarget.lib LLVMTransformUtils.lib LLVMVectorize.lib LLVMWindowsManifest.lib LLVMX86AsmParser.lib LLVMX86AsmPrinter.lib LLVMX86CodeGen.lib LLVMX86Desc.lib LLVMX86Disassembler.lib LLVMX86Info.lib LLVMX86Utils.lib LLVMXRay.lib \
      "$(LUAJIT_DIR)\src\lua51.lib" Shlwapi.lib dbghelp.lib Version.lib
!ELSE IF $(LLVM_VERSION_SHORT)==50
LIBS= clangAnalysis.lib clangARCMigrate.lib clangAST.lib clangASTMatchers.lib clangBasic.lib clangCodeGen.lib clangDriver.lib clangDynamicASTMatchers.lib clangEdit.lib clangFormat.lib clangFrontend.lib clangFrontendTool.lib clangIndex.lib clangLex.lib clangParse.lib clangRewrite.lib clangRewriteFrontend.lib clangSema.lib clangSerialization.lib clangStaticAnalyzerCheckers.lib clangStaticAnalyzerCore.lib clangStaticAnalyzerFrontend.lib clangTooling.lib clangToolingCore.lib clangToolingRefactor.lib libclang.lib LLVMAnalysis.lib LLVMAsmParser.lib LLVMAsmPrinter.lib LLVMBinaryFormat.lib LLVMBitReader.lib LLVMBitWriter.lib LLVMCodeGen.lib LLVMCore.lib LLVMCoroutines.lib LLVMCoverage.lib LLVMDebugInfoCodeView.lib LLVMDebugInfoDWARF.lib LLVMDebugInfoMSF.lib LLVMDebugInfoPDB.lib LLVMDemangle.lib LLVMDlltoolDriver.lib LLVMExecutionEngine.lib LLVMGlobalISel.lib LLVMInstCombine.lib LLVMInstrumentation.lib LLVMInterpreter.lib LLVMipo.lib LLVMIRReader.lib LLVMLibDriver.lib LLVMLineEditor.lib LLVMLinker.lib LLVMLTO.lib LLVMMC.lib LLVMMCDisassembler.lib LLVMMCJIT.lib LLVMMCParser.lib LLVMMIRParser.lib LLVMNVPTXAsmPrinter.lib LLVMNVPTXCodeGen.lib LLVMNVPTXDesc.lib LLVMNVPTXInfo.lib LLVMObjCARCOpts.lib LLVMObject.lib LLVMObjectYAML.lib LLVMOption.lib LLVMOrcJIT.lib LLVMPasses.lib LLVMProfileData.lib LLVMRuntimeDyld.lib LLVMScalarOpts.lib LLVMSelectionDAG.lib LLVMSupport.lib LLVMSymbolize.lib LLVMTableGen.lib LLVMTarget.lib LLVMTransformUtils.lib LLVMVectorize.lib LLVMX86AsmParser.lib LLVMX86AsmPrinter.lib LLVMX86CodeGen.lib LLVMX86Desc.lib LLVMX86Disassembler.lib LLVMX86Info.lib LLVMX86Utils.lib LLVMXRay.lib \
      "$(LUAJIT_DIR)\src\lua51.lib" Shlwapi.lib dbghelp.lib Version.lib
!ELSE IF $(LLVM_VERSION_SHORT)==40
LIBS= clangAnalysis.lib clangARCMigrate.lib clangAST.lib clangASTMatchers.lib clangBasic.lib clangCodeGen.lib clangDriver.lib clangDynamicASTMatchers.lib clangEdit.lib clangFormat.lib clangFrontend.lib clangFrontendTool.lib clangIndex.lib clangLex.lib clangParse.lib clangRewrite.lib clangRewriteFrontend.lib clangSema.lib clangSerialization.lib clangStaticAnalyzerCheckers.lib clangStaticAnalyzerCore.lib clangStaticAnalyzerFrontend.lib clangTooling.lib clangToolingCore.lib libclang.lib LLVMAnalysis.lib LLVMAsmParser.lib LLVMAsmPrinter.lib LLVMBitReader.lib LLVMBitWriter.lib LLVMCodeGen.lib LLVMCore.lib LLVMCoroutines.lib LLVMCoverage.lib LLVMDebugInfoCodeView.lib LLVMDebugInfoDWARF.lib LLVMDebugInfoMSF.lib LLVMDebugInfoPDB.lib LLVMDemangle.lib LLVMExecutionEngine.lib LLVMGlobalISel.lib LLVMInstCombine.lib LLVMInstrumentation.lib LLVMInterpreter.lib LLVMipo.lib LLVMIRReader.lib LLVMLibDriver.lib LLVMLineEditor.lib LLVMLinker.lib LLVMLTO.lib LLVMMC.lib LLVMMCDisassembler.lib LLVMMCJIT.lib LLVMMCParser.lib LLVMMIRParser.lib LLVMNVPTXAsmPrinter.lib LLVMNVPTXCodeGen.lib LLVMNVPTXDesc.lib LLVMNVPTXInfo.lib LLVMObjCARCOpts.lib LLVMObject.lib LLVMObjectYAML.lib LLVMOption.lib LLVMOrcJIT.lib LLVMPasses.lib LLVMProfileData.lib LLVMRuntimeDyld.lib LLVMScalarOpts.lib LLVMSelectionDAG.lib LLVMSupport.lib LLVMSymbolize.lib LLVMTableGen.lib LLVMTarget.lib LLVMTransformUtils.lib LLVMVectorize.lib LLVMX86AsmParser.lib LLVMX86AsmPrinter.lib LLVMX86CodeGen.lib LLVMX86Desc.lib LLVMX86Disassembler.lib LLVMX86Info.lib LLVMX86Utils.lib LLVMXRay.lib \
      "$(LUAJIT_DIR)\src\lua51.lib" Shlwapi.lib dbghelp.lib Version.lib
!ELSE # Only tested for 3.5.2
LIBS= clangAnalysis.lib clangARCMigrate.lib clangAST.lib clangASTMatchers.lib   \
      clangBasic.lib clangCodeGen.lib clangDriver.lib                           \
      clangDynamicASTMatchers.lib clangEdit.lib clangFormat.lib                 \
      clangFrontend.lib clangFrontendTool.lib clangIndex.lib clangLex.lib       \
      clangParse.lib clangRewrite.lib clangRewriteFrontend.lib clangSema.lib    \
      clangSerialization.lib clangStaticAnalyzerCheckers.lib                    \
      clangStaticAnalyzerCore.lib clangStaticAnalyzerFrontend.lib               \
      clangTooling.lib LLVMAnalysis.lib LLVMAsmParser.lib LLVMAsmPrinter.lib    \
      LLVMBitReader.lib LLVMBitWriter.lib LLVMCodeGen.lib LLVMCore.lib          \
      LLVMDebugInfo.lib LLVMExecutionEngine.lib LLVMInstCombine.lib             \
      LLVMInstrumentation.lib LLVMInterpreter.lib LLVMipa.lib LLVMipo.lib       \
      LLVMIRReader.lib LLVMJIT.lib LLVMLineEditor.lib LLVMLinker.lib            \
      LLVMLTO.lib LLVMMC.lib LLVMMCAnalysis.lib LLVMMCDisassembler.lib          \
      LLVMMCJIT.lib LLVMMCParser.lib LLVMNVPTXAsmPrinter.lib                    \
      LLVMNVPTXCodeGen.lib LLVMNVPTXDesc.lib LLVMNVPTXInfo.lib                  \
      LLVMObjCARCOpts.lib LLVMObject.lib LLVMOption.lib LLVMProfileData.lib     \
      LLVMRuntimeDyld.lib LLVMScalarOpts.lib LLVMSelectionDAG.lib               \
      LLVMSupport.lib LLVMTableGen.lib LLVMTarget.lib LLVMTransformUtils.lib    \
      LLVMVectorize.lib LLVMX86AsmParser.lib LLVMX86AsmPrinter.lib              \
      LLVMX86CodeGen.lib LLVMX86Desc.lib LLVMX86Disassembler.lib                \
      LLVMX86Info.lib LLVMX86Utils.lib                                          \
      "$(LUAJIT_DIR)\src\lua51.lib" Shlwapi.lib
!ENDIF

!ENDIF

LIBPATHS = /LIBPATH:"$(LLVM_DIR)\lib"

!IFNDEF CLANG_RESOURCE_DIRECTORY
CLANG_RESOURCE_DIRECTORY="$(LLVM_DIR)\lib\clang\$(LLVM_VERSION)"
!ENDIF

TERRALIB_SRC = "$(SRC)\lctype.cpp" "$(SRC)\llex.cpp" "$(SRC)\lobject.cpp" "$(SRC)\lparser.cpp" "$(SRC)\lstring.cpp" "$(SRC)\lzio.cpp" "$(SRC)\tcompiler.cpp" "$(SRC)\tcuda.cpp" "$(SRC)\tcwrapper.cpp" "$(SRC)\tdebug.cpp" "$(SRC)\terra.cpp" "$(SRC)\tinline.cpp" "$(SRC)\tkind.cpp" "$(SRC)\tllvmutil.cpp" "$(SRC)\tinternalizedfiles.cpp" "$(SRC)\treadnumber.c" "$(SRC)\lj_strscan.c"
CPP=cl
LINK=link

LUAJIT = $(LUAJIT_DIR)\src\luajit.exe

CPPFLAGS = /MP8 /nologo /EHsc /w /MD /Zi /D_CRT_SECURE_NO_DEPRECATE /DNOMINMAX /DTERRA_LLVM_HEADERS_HAVE_NDEBUG /DTERRA_VERSION_STRING="\"$(TERRA_VERSION)\"" \
           /I$(LUAJIT_DIR)\src "/I$(SRC)" "/I$(BUILD)" "/I$(TERRA_DIR)\release\include\terra" "/I$(LLVM_DIR)\include" "/I$(TERRA_DIR)\msvc" \
           /DLLVM_VERSION=$(LLVM_VERSION_SHORT) \
           $(CUDA_INCLUDES)

all:	..\release\bin\terra.exe

$(LUAJIT) $(TERRA_DIR)\release\include\terra\lua.h:	"$(LUAJIT_DIR)\src\luajit.c"
	cd "$(LUAJIT_DIR)\src"
	msvcbuild.bat
	copy lua.h "$(TERRA_DIR)\release\include\terra"
	copy lualib.h "$(TERRA_DIR)\release\include\terra"
	copy lauxlib.h "$(TERRA_DIR)\release\include\terra"
	copy luaconf.h "$(TERRA_DIR)\release\include\terra"

"$(BUILD)\terralib.h" "$(BUILD)\strict.h" "$(BUILD)\cudalib.h" "$(BUILD)\asdl.h" "$(BUILD)\terralist.h":	"$(SRC)\terralib.lua" "$(SRC)\strict.lua" "$(SRC)\cudalib.lua" "$(SRC)\asdl.lua" "$(SRC)\terralist.lua" $(LUAJIT) "$(TERRA_DIR)\release\include\terra\lua.h"
	set LUA_PATH=$(LUAJIT_DIR)\src\?.lua
	$(LUAJIT) -bg "$(SRC)\terralib.lua" "$(BUILD)\terralib.h"
	$(LUAJIT) -bg "$(SRC)\strict.lua" "$(BUILD)\strict.h"
	$(LUAJIT) -bg "$(SRC)\cudalib.lua" "$(BUILD)\cudalib.h"
	$(LUAJIT) -bg "$(SRC)\asdl.lua" "$(BUILD)\asdl.h"
	$(LUAJIT) -bg "$(SRC)\terralist.lua" "$(BUILD)\terralist.h"

"$(BUILD)\internalizedfiles.h":	$(LUAJIT)  "$(SRC)\geninternalizedfiles.lua"
	cd "$(TERRA_DIR)"
	$(LUAJIT) src\geninternalizedfiles.lua  build\internalizedfiles.h $(CLANG_RESOURCE_DIRECTORY) "%.h$$" $(CLANG_RESOURCE_DIRECTORY) "%.modulemap$$" "$(TERRA_DIR)\lib" "%.t$$" 

EXPORTS = /EXPORT:terra_init /EXPORT:terra_initwithoptions /EXPORT:terra_load /EXPORT:terra_loadfile /EXPORT:terra_loadbuffer /EXPORT:terra_loadstring /EXPORT:terra_llvmshutdown

"$(BUILD)\terra.obj": "$(BUILD)\internalizedfiles.h" "$(BUILD)\terralib.h" "$(BUILD)\strict.h" "$(BUILD)\cudalib.h" $(TERRALIB_SRC)
	cd "$(BUILD)"
	$(CPP) $(CPPFLAGS) /c $(TERRALIB_SRC)

"$(TERRA_DIR)\release\bin\terra.dll": "$(BUILD)\terra.obj"
	if not exist "$(TERRA_DIR)\release\bin" mkdir "$(TERRA_DIR)\release\bin"
	if not exist "$(TERRA_DIR)\release\lib" mkdir "$(TERRA_DIR)\release\lib"
	cd "$(TERRA_DIR)\release\bin"
	$(LINK) /nologo /MACHINE:$(VSCMD_ARG_TGT_ARCH) /DLL /DEBUG /PDB:terralib.pdb /out:terra.dll /IMPLIB:terra.lib "$(BUILD)/*.obj" $(LIBS) $(LIBPATHS) $(EXPORTS)
	move terra.lib ..\lib\terra.lib

!IFNDEF MSVC_REDIST_PATH
MSVC_REDIST_PATH=Microsoft.VC142.CRT\msvcp140.dll
!ENDIF

..\release\bin\terra.exe: "$(TERRA_DIR)\release\bin\terra.dll" "$(SRC)\main.cpp"
	cd "$(TERRA_DIR)"
	copy "$(LUAJIT_DIR)\src\lua51.dll" release\bin
	copy "$(LUAJIT_DIR)\src\lua51.lib" release\lib
  copy "$(VCTOOLSREDISTDIR)$(VSCMD_ARG_TGT_ARCH)\$(MSVC_REDIST_PATH)" release\bin
  cd "$(TERRA_DIR)\build"
	$(CPP) $(CPPFLAGS) /Fe:"$(TERRA_DIR)\release\bin\terra.exe" "$(SRC)\main.cpp" "$(TERRA_DIR)\msvc\ext\getopt.c" "$(TERRA_DIR)\msvc\ext\getopt_long.c" "$(TERRA_DIR)\release\lib\terra.lib" "$(LUAJIT_DIR)\src\lua51.lib"

clean:
	del ..\build\*.obj ..\build\*.h ..\build\terra.lib ..\release\bin\terra.dll ..\release\lib\terra.lib ..\release\bin\terra.exe

.SUFFIXES:
