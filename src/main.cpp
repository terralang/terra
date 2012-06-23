#include <stdio.h>
extern "C" {
    #include <lua.h>
    #include <lualib.h>
    #include <lauxlib.h>
}
#include "terra.h"

static void doerror(lua_State * L) {
    printf("%s\n",luaL_checkstring(L,-1));
    exit(1);
}

int main(int argc, char ** argv) {
    lua_State * L = luaL_newstate();
    luaL_openlibs(L);
    if(terra_init(L))
        doerror(L);
    
    for(int i = 1; i < argc; i++) {
        if(terra_loadfile(L,argv[i]) || lua_pcall(L, 0, LUA_MULTRET, 0)) {
            doerror(L);
        }
    }
    return 0;
}
