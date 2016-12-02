package = "terra"
version = "scm-1"

source = {
   url = "git://github.com/zdevito/terra.git",
   branch = "develop",
}

description = {
   summary = "A low-level counterpart to Lua.",
   homepage = "",
   license = "MIT",
}
build = {
   type = "make",
   variables = {
      LUA="$(LUA)",
      LUA_LIB="$(LUA_LIBDIR)/libluajit.so",
      LUA_INCLUDE="$(LUA_INCDIR)",
      TERRA_RPATH="$(LUA_LIBDIR)",
      TERRA_EXTERNAL_LUA="1",
      INSTALL_BINARY_DIR="$(LUA_BINDIR)",
      INSTALL_LIBRARY_DIR="$(LUA_LIBDIR)",
      INSTALL_SHARE_DIR="$(LUA_BINDIR)/../share",
      INSTALL_INCLUDE_DIR="$(LUA_INCDIR)",
      INSTALL_LUA_LIBRARY_DIR="$(LIBDIR)",
      TERRA_HOME="$(abspath $(LUA_BINDIR)/..)",
   },
   platforms = {
      macosx = {
         variables = {
            LUA_LIB="$(LUA_LIBDIR)/libluajit.dylib",
         }
      }
   }
}
