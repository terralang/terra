C = terralib.includecstring [[
    #include "../build/LuaJIT-2.0.1/src/lua.h"
    #include "../build/LuaJIT-2.0.1/src/lauxlib.h"
]]

local s = C.luaL_newstate()
assert(C.lua_gettop(s) == 0)

