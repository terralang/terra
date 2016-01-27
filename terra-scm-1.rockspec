package = "terra"
version = "scm-1"

source = {
   url = "git://github.com/zdevito/terra.git",
   branch = "master",
}

description = {
   summary = "A low-level counterpart to Lua.",
   homepage = "",
   license = "MIT",
}

build = {
   type = "command",
   build_command = [[
make clean
libdir=$(LUA_LIBDIR)
LUAJIT_PREFIX=${libdir%/lib}
make LUAJIT_PREFIX=$LUAJIT_PREFIX CXX=clang++ CC=clang LLVM_CONFIG=$(LUA_BINDIR)/llvm-config
   ]],
   install_command = [[
make PREFIX=$(PREFIX) install
   ]],
}