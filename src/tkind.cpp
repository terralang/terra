#include "terrastate.h"
#include "tkind.h"
#include <assert.h>
extern "C" {
#include "lua.h"
}
static const char * kindtostr[] = {
#define T_KIND_STRING(a,str) str,
    T_KIND_LIST(T_KIND_STRING)
    NULL
};
const char * tkindtostr(T_Kind k) {
    assert(k < T_NUM_KINDS);
    return kindtostr[k];
}

void terra_kindsinit(terra_State * T) {
    lua_State * L = T->L;
    lua_getfield(L,LUA_GLOBALSINDEX,"terra");
    lua_newtable(L);
    lua_setfield(L,-2,"kinds");
    lua_getfield(L,-1,"kinds");
    int kinds = lua_gettop(L);
    for(int i = 0; i < T_NUM_KINDS; i++) {
        lua_pushstring(L,tkindtostr((T_Kind) i));
        lua_rawseti(L,kinds,i);
        lua_pushinteger(L,i);
        lua_setfield(L,kinds,tkindtostr((T_Kind) i));
    }
    assert(lua_gettop(L) == kinds);
    lua_pop(L,2); //kinds and terra object
}