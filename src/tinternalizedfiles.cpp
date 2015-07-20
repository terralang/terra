//auto-generate files that defines the data for the internalized headers
#include "stdint.h"
#include "internalizedfiles.h"
#include "terra.h"

void terra_registerinternalizedfiles(lua_State * L, int terratable) {
    lua_getfield(L,terratable,"registerinternalizedfiles");
    lua_pushlightuserdata(L,&headerfile_names[0]);
    lua_pushlightuserdata(L,&headerfile_contents[0]);
    lua_pushlightuserdata(L,&headerfile_sizes[0]);
    lua_call(L,3,0);
}