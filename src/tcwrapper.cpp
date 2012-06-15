#include "tcwrapper.h"

#include <assert.h>
#include <stdio.h>
extern "C" {
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
    
}
int include_c(lua_State * L) {
    terra_State * T = (terra_State*) lua_topointer(L,lua_upvalueindex(1));
    assert(T->L == L);
    const char * fname = luaL_checkstring(L, -1);
    printf("loading %s\n",fname);
    
    //TODO: use clang to populate table of external functions
    
    lua_newtable(L); //return a table of loaded functions
    return 1;
}

void terra_cwrapperinit(terra_State * T) {
    lua_getfield(T->L,LUA_GLOBALSINDEX,"terra");
    lua_pushlightuserdata(T->L,(void*)T);
    lua_pushcclosure(T->L,include_c,1);
    lua_setfield(T->L,-2,"includec");
    lua_pop(T->L,-1); //terra object
}