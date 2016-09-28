local struct lua_State
lua_getfield = terralib.externfunction("lua_getfield",{&lua_State,int,rawstring} -> int)
lua_gettop = terralib.externfunction("lua_gettop",{&lua_State} -> int)
printf = terralib.externfunction("printf", terralib.types.funcpointer(rawstring,int,true))
terra foo(L : &lua_State) : int
    printf("stack has %d arguments\n",lua_gettop(L))
    lua_getfield(L,1,"a")
    return 1
end
local foob = terralib.bindtoluaapi(foo:compile())

assert(type(foob) == "function")

a = {}
assert(a == foob(_G,2,3))
