@echo off
rem This batch file should be used inside a Native Tools Command Prompt as follows:
rem build.bat luajit_dir llvm_install_dir [terra_version] [llvm_short_version]
rem 
rem An example invocation:
rem build.bat D:\Projects\LuaJIT-2.0.5 D:\Projects\llvm-6.0.1.src\build\install 1.0.0

IF "%1"=="" GOTO MissingNo
IF "%2"=="" GOTO MissingNo

SET LUAJIT_DIR=%1
SET LLVM_DIR=%2
SET TERRA_VERSION=%3
SET LLVM_VERSION_SHORT=%4 

pushd ..
SET TERRA_DIR=%CD%
popd

rem Older versions of visual studio are missing environment variables, so we polyfill them
IF "%VCToolsVersion%"=="" SET VCToolsVersion=%VisualStudioVersion%
IF "%VCTOOLSREDISTDIR%"=="" SET VCTOOLSREDISTDIR=%VCINSTALLDIR%redist\
IF "%VSCMD_ARG_TGT_ARCH%"=="" SET VSCMD_ARG_TGT_ARCH=%Platform%

SET VC_TOOLS_MAJOR=%VCToolsVersion:~0,2%
SET VC_TOOLS_MINOR=%VCToolsVersion:~3,1%

rem Microsoft apparently doesn't actually change the version msvcp140.dll unless the major version number changes
SET MSVC_REDIST_PATH=Microsoft.VC%VC_TOOLS_MAJOR%%VC_TOOLS_MINOR%.CRT\msvcp%VC_TOOLS_MAJOR%0.dll

pushd %LLVM_DIR%\lib\clang
FOR /d %%i IN (*) DO SET LLVM_VERSION=%%i
popd

ECHO Set TERRA_DIR to "%TERRA_DIR%"
ECHO Set MSVC_REDIST_PATH to "%MSVC_REDIST_PATH%"
ECHO Set LLVM_VERSION to "%LLVM_VERSION%"

IF NOT "%4"=="" GOTO SkipLLVM
SET LLVM_VERSION_SHORT=%LLVM_VERSION:~0,1%%LLVM_VERSION:~2,1%

ECHO Set LLVM_VERSION_SHORT to "%LLVM_VERSION_SHORT%"

:SkipLLVM
CALL nmake
ECHO Done.
GOTO Done

:MissingNo
  ECHO Please provide both the LuaJIT install directory and the LLVM install directory!
  
:Done
