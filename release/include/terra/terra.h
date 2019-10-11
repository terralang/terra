/* See Copyright Notice in ../LICENSE.txt */

#ifndef terra_h
#define terra_h

#if __cplusplus
extern "C" {
#endif

#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"

int terra_init(lua_State *L);

typedef struct { /* default values are 0 */
    int verbose; /*-v, print more debugging info (can be 1 for some, 2 for more) */
    int debug;   /*-g, turn on debugging symbols and base pointers */
    int usemcjit;
    char *cmd_line_chunk;
} terra_Options;
int terra_initwithoptions(lua_State *L, terra_Options *options);

int terra_load(lua_State *L, lua_Reader reader, void *data, const char *chunkname);
int terra_loadfile(lua_State *L, const char *file);
int terra_loadbuffer(lua_State *L, const char *buf, size_t size, const char *name);
int terra_loadstring(lua_State *L, const char *s);
void terra_llvmshutdown();

#define terra_dofile(L, fn) (terra_loadfile(L, fn) || lua_pcall(L, 0, LUA_MULTRET, 0))

#define terra_dostring(L, s) (terra_loadstring(L, s) || lua_pcall(L, 0, LUA_MULTRET, 0))

#if __cplusplus
} /*extern C*/
#endif

#endif
