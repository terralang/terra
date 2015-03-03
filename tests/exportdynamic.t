terralib.includepath = terralib.terrahome.."/include"
C = terralib.includecstring [[
    #include "lua.h"
    #include "lauxlib.h"
]]

local s = C.luaL_newstate()
assert(C.lua_gettop(s) == 0)

