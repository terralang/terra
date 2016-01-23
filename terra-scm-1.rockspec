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

    make LUAJIT_LIB=$(LUA_LIBDIR)/libluajit-5.1.a \
        CXX=clang++ \
        CC=clang \
        LLVM_CONFIG=$(LUA_BINDIR)/llvm-config \
        LUAJIT_INCLUDE=$(LUA_INCDIR) \
        LUAJIT_PATH=$(LUA_INCDIR)/../share/luajit-2.0.4/?.lua \
        LUAJIT=$(LUA)

   ]],
   install_command = [[
      mv release/bin/terra $(LUA_BINDIR)/ # TODO: or $(BINDIR)?
      mv release/include/terra $(LUA_INCDIR)/
      mv release/lib/* $(LIBDIR)/
   ]],
}
