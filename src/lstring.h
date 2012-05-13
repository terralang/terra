/*
** $Id: lstring.h,v 1.46 2010/04/05 16:26:37 roberto Exp $
** String table (keep all strings handled by Lua)
** See Copyright Notice in lua.h
*/

#ifndef lstring_h
#define lstring_h

#include "lobject.h"
#include "putil.h"

#define sizestring(s)	(sizeof(union TString)+((s)->len+1)*sizeof(char))

/* get the actual string (array of bytes) from a TString */
#define getstr(ts)	cast(const char *, (ts) + 1)


#define luaS_newliteral(L, s)	(luaS_newlstr(L, "" s, \
                                 (sizeof(s)/sizeof(char))-1))


/*
** as all string are internalized, string equality becomes
** pointer equality
*/
#define eqstr(a,b)	((a) == (b))

LUAI_FUNC void luaS_resize (lua_State *L, int newsize);
LUAI_FUNC TString *luaS_newlstr (lua_State *L, const char *str, size_t l);
LUAI_FUNC TString *luaS_new (lua_State *L, const char *str);


#endif
