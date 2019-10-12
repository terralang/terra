/*
** $Id: lstring.c,v 2.19 2011/05/03 16:01:57 roberto Exp $
** String table (keeps all strings handled by Lua)
** See Copyright Notice in lua.h
*/


#include <string.h>

#define lstring_c
#define LUA_CORE

#include "lobject.h"
#include "lstring.h"

#include <assert.h>


TString *luaS_newlstr (terra_State *L, const char *str, size_t l) {
    //get the tstring_table
    lua_pushlightuserdata(L->L, &L->tstring_table);
    lua_rawget(L->L, LUA_REGISTRYINDEX);
    //look up the string
    lua_pushlstring(L->L, str, l);
    lua_pushvalue(L->L,-1);
    lua_gettable(L->L, -3);
    if(lua_isnil(L->L, -1)) {
        lua_pop(L->L,1); //nil
        TString * string = (TString *) lua_newuserdata(L->L, sizeof(TString));
        string->string = luaL_checkstring(L->L, -2);
        string->reserved = 0;
        lua_rawset(L->L, -3);
        lua_pop(L->L,1); //<table>
        return string;
    } else {
        TString * string = (TString *) lua_touserdata(L->L, -1);
        lua_pop(L->L,3); //<userdata> <string> <table>
        return string;
    }
    
}


TString *luaS_new (terra_State *L, const char *str) {
  return luaS_newlstr(L, str, strlen(str));
}
TString * luaS_vstringf(terra_State * L, const char * fmt, va_list ap) {
    int N = 128;
    char stack_buf[128];
    char * buf = stack_buf;
    while(1) {
        va_list cur;
#if _MSC_VER < 1900 && defined(_WIN32)
        // Apparently this is fine for the MSVC x64 compiler.
        // See: http://www.bailopan.net/blog/?p=51
        cur = ap;
#else
        va_copy(cur,ap);
#endif
        int n = vsnprintf(buf, N, fmt, cur);
        va_end(cur);
        if(n > -1 && n < N) {
            TString * r = luaS_newlstr(L,buf,n);
            if(buf != stack_buf)
                free(buf);
            return r;
        }
        if(n > -1)
            N = n + 1;
        else
            N *= 2;
        if(buf != stack_buf)
            free(buf);
        buf = (char*) malloc(N);
    }
}

TString * luaS_stringf(terra_State * L, const char * fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    TString * ts = luaS_vstringf(L,fmt,ap);
    va_end(ap);
    return ts;
}
const char * luaS_cstringf(terra_State * L, const char * fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    TString * ts = luaS_vstringf(L,fmt,ap);
    va_end(ap);
    return getstr(ts);
}

