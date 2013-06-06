
Building Terra on Windows
==========================

- You'll need to define the User Macros LLVM_ROOT and LLVM_BUILD_ROOT (these may be the same path, if you did an in-source build of LLVM). The simplest place to put these is in the Microsoft.Cpp.x64.user Property Sheet. Use forward slashes for these paths, as they will be embedded in strings.

- Downloading and installing LuaJIT requires an installation of [curl](http://curl.haxx.se/download.html). It also requires an installation of tar (usually obtained through cygwin or MinGW's MSYS)

- If you want to save executables, Terra must be run in an environment where the `VC/bin/amd64/vcvars64.bat` script has been run (Terra needs the paths that this sets up in order to find the correct system linker). In particular, you'll need to do this before running Terra's tests.