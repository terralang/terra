local ffi = require 'ffi'
-- test that the dynamic library for terra was built correctly
-- by compiling a new program that links against it and running it
terralib.includepath = terralib.terrahome.."/include/terra"
C = terralib.includecstring [[
#include <stdio.h>
#include "terra.h"
]]

local libpath = terralib.terrahome.."/lib"

terra doerror(L : &C.lua_State)
    C.printf("%s\n",C.luaL_checklstring(L,-1,nil))
end

local thecode = "terra foo() return 1 end print(foo())"

terra main(argc : int, argv : &rawstring)
    var L = C.luaL_newstate();
    C.luaL_openlibs(L);
    if C.terra_init(L) ~= 0 then
        doerror(L)
    end
    if C.terra_loadstring(L,thecode) ~= 0 or C.lua_pcall(L, 0, -1, 0) ~= 0 then
        doerror(L)
    end
    return 0;
end

local function exists(path)
  local f = io.open(path, "r")
  local result = f ~= nil
  if f then f:close() end
  return result
end

if ffi.os ~= "Windows" then
    print(libpath)
    local libext = ".so"
    if ffi.os == "OSX" then
      libext = ".dylib"
    end

    local libname = "terra"..libext

    local flags = terralib.newlist {"-Wl,-rpath,"..libpath,libpath.."/"..libname}
    local lua_lib = libpath.."/".."libluajit-5.1"..libext
    if exists(lua_lib) then
      flags:insert(lua_lib)
    end
    print(flags:concat(" "))
    if ffi.os == "OSX" then
        flags:insertall {"-pagezero_size","10000", "-image_base", "100000000"}
    end

    terralib.saveobj("dynlib",{main = main},flags)

    assert(0 == os.execute("./dynlib"))

else
    local putenv = terralib.externfunction("_putenv", rawstring -> int)
    local flags = {libpath.."\\terra.lib",libpath.."\\lua51.lib"}
    terralib.saveobj("dynlib.exe",{main = main},flags)
    putenv("Path="..os.getenv("Path")..";"..terralib.terrahome.."\\bin") --make dll search happy
    assert(0 == os.execute(".\\dynlib.exe"))
end
