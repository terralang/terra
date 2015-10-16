terralib.includepath = terralib.terrahome.."/include/terra"
C = terralib.includecstring [[
    #include "lua.h"
    #include "lauxlib.h"
    #include "stdio.h"
]]

terra foo(L : &C.lua_State) : int
    C.printf("stack has %d arguments\n",C.lua_gettop(L))
    C.lua_getfield(L,1,"a")
    return 1
end
local foob = terralib.bindtoluaapi(foo:getpointer())

assert(type(foob) == "function")

a = {}
assert(a == foob(_G,2,3))
