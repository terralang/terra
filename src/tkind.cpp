/* See Copyright Notice in ../LICENSE.txt */

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
    for(int i = 0; i < T_NUM_KINDS; i++) {
        lua_pushnumber(L,i);
        lua_setfield(L,-2,tkindtostr((T_Kind) i));
    }
    lua_setfield(L,-2,"kinds");
    lua_pop(L,1); //terra object
}