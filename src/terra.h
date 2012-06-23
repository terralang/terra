#ifndef terra_h
#define terra_h

extern "C" {
#include <lua.h>
}

int terra_init(lua_State * L);
int terra_loadfile(lua_State * T, const char * file);
#endif
