// auto-generate files that defines the data for the internalized headers
#include "stdint.h"
#include "internalizedfiles.h"
#include "terra.h"

void terra_registerinternalizedfiles(lua_State* L, int terratable) {
    lua_getfield(L, terratable, "registerinternalizedfile");
    for (int i = 0; headerfile_names[i] != NULL; i++) {
        lua_pushvalue(L, -1);
        lua_pushstring(L, headerfile_names[i]);
        lua_pushlightuserdata(L, (void*)headerfile_contents[i]);
        lua_pushnumber(L, headerfile_sizes[i]);
        lua_call(L, 3, 0);
    }
    lua_pop(L, 1);
}
