
Building Terra on Windows using Visual Studio 2015 or 2019
==================================================

1. To build Terra you need to download, build, and install Clang+LLVM 6.0 (or 7.0). You should end up with a diretory with `bin/` `lib/` and `include/` directories with the clang+llvm binaries and library files. You also need to download LuaJIT-2.0.5 and unzip it somewhere. Builds for windows are available here, but may not be up to date: https://github.com/Mx7f/llvm-package-windows/releases

2. Open an x64 Native Tools Command Prompt for VS (or the x86 Native tools if you want to compile 32-bit) and navigate to this folder, then run `build.bat your_luajit_directory your_llvm_directory`.
 
3. To clean build results, simply run `nmake clean` from the Native Tools command prompt after navigating to this folder - the .bat file isn't necessary for this operation.