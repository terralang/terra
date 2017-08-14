LLVM_CONFIG="/usr/local/bin/llvm-config-3.7"
CXXFLAGS="$CXXFLAGS -nostdinc++ -I/usr/local/opt/llvm@3.7/lib/llvm-3.7/include/c++/v1"
LDFLAGS="$LDFLAGS -L/usr/local/opt/llvm@3.7/lib/llvm-3.7/lib"
