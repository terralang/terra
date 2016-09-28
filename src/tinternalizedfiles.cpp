//auto-generate files that defines the data for the internalized headers
#include "stdint.h"
#include "internalizedfiles.h"
#include "terra.h"
#include <string>

int terra_loadbytecodes(lua_State * L, const unsigned char * bytecodes, size_t size, const char * name) {
  int err = luaL_loadbuffer(L, (const char *) bytecodes, size, name);
  if(err)
    return err;
  
  lua_getglobal(L,"package");
  lua_getfield(L,-1,"preload");
  lua_pushvalue(L,-3);
  lua_setfield(L,-2,name);
  lua_pop(L,3);
  return 0;
}

int terra_registerinternalizedfiles(lua_State * L, int terratable) {
    
#ifndef TERRA_EXTERNAL_TERRALIB
    for(int i = 0; luafile_indices[i] != -1; i++) {
        int idx = luafile_indices[i];
        std::string name = headerfile_names[idx];
        int err = terra_loadbytecodes(L,headerfile_contents[idx],headerfile_sizes[idx],name.substr(1,name.size() - 4).c_str());
        if(err)
            return err;
    }
#else
    lua_getglobal(L,"package");
    lua_getfield(L,-1,"path");
    lua_pushstring(L,";");
    lua_pushstring(L,TERRA_EXTERNAL_TERRALIB);
    lua_concat(L,3);
    lua_setfield(L,-2,"path");
    lua_pop(L,1);
#endif
    
    lua_getglobal(L,"require");
    lua_pushstring(L,"terralib");
    int err = lua_pcall(L,1,0,0);
    if(err)
        return err;
    
    lua_getfield(L,terratable,"registerinternalizedfile");
    for(int i = 0; headerfile_names[i] != NULL; i++) {
        lua_pushvalue(L,-1);
        lua_pushstring(L,headerfile_names[i]);
        lua_pushlightuserdata(L,(void*)headerfile_contents[i]);
        lua_pushnumber(L,headerfile_sizes[i]);
        lua_call(L,3,0);
    }
    lua_pop(L,1);
    
    return 0;
}