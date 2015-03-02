-- test that the dynamic library for terra was built correctly
-- by compiling a new program that links against it and running it
terralib.includepath = "../release/include"
C = terralib.includecstring [[
#include <stdio.h>
#include "terra.h"
]]


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


local flags = terralib.newlist {"-L../release","-Wl,-rpath,../release","-lterra"}
if require("ffi").os == "OSX" then
    flags:insertall {"-pagezero_size","10000", "-image_base", "100000000"}
end

terralib.saveobj("dynlib",{main = main},flags)

assert(0 == os.execute("./dynlib"))