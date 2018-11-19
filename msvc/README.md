
Building Terra on Windows using Visual Studio 2015
==================================================

1. To build Terra you need to download, build, and install Clang+LLVM 6.0. You should end up with a diretory with "bin/" "lib/" and "include/" directories with the clang+llvm binaries and library files. You also need to download LuaJIT-2.0.5 and unzip it somewhere.

2. Edit msvc/Makefile to point to the dependencies (details are in the Makefile)

3. Run build.bat (You may have to edit it to point to your installation of VS2015)
 
