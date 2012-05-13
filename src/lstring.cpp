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

LUAI_FUNC void luaS_resize (lua_State *L, int newsize) {
  //printf("\n\n\nRESIZING\n\n\n");
  int i;
  stringtable *tb = &L->strt;
  if (newsize > tb->size) {
	tb->hash = (TString**) realloc(tb->hash,newsize * sizeof(TString*));
	for (i = tb->size; i < newsize; i++) tb->hash[i] = NULL;
  }
  /* rehash */
  for (i=0; i<tb->size; i++) {
    TString *p = tb->hash[i];
    tb->hash[i] = NULL;
    while (p) {  /* for each node in the list */
      TString *next = p->next;  /* save next */
      unsigned int h = lmod(p->hash, newsize);  /* new position */
      p->next = tb->hash[h];  /* chain it */
      tb->hash[h] = p;
      p = next;
    }
  }
  if (newsize < tb->size) {
    /* shrinking slice must be empty */
    assert(tb->hash[newsize] == NULL && tb->hash[tb->size - 1] == NULL);
    tb->hash = (TString**) realloc(tb->hash,newsize * sizeof(TString*));
  }
  tb->size = newsize;
}


static TString *newlstr (lua_State *L, const char *str, size_t l,
                                       unsigned int h) {
  size_t totalsize;  /* total size of TString object */
  TString **list;  /* (pointer to) list where it will be inserted */
  TString *ts;
  stringtable *tb = &L->strt;
  //TODO: audit
  //if (l+1 > (MAX_SIZET - sizeof(TString))/sizeof(char))
  //  luaM_toobig(L);
  if (tb->nuse >= cast(lu_int32, tb->size) && tb->size <= MAX_INT/2)
    luaS_resize(L, tb->size*2);  /* too crowded */
  totalsize = sizeof(TString) + ((l + 1) * sizeof(char));
  list = &tb->hash[lmod(h, tb->size)];
  ts =(TString*) malloc(totalsize);
  ts->next = *list;
  *list = ts;
  ts->len = l;
  ts->hash = h;
  ts->reserved = 0;
  memcpy(ts+1, str, l*sizeof(char));
  ((char *)(ts+1))[l] = '\0';  /* ending 0 */
  tb->nuse++;
  return ts;
}


TString *luaS_newlstr (lua_State *L, const char *str, size_t l) {
  TString *o;
  unsigned int h = cast(unsigned int, l);  /* seed */
  size_t step = (l>>5)+1;  /* if string is too long, don't hash all its chars */
  size_t l1;
  for (l1=l; l1>=step; l1-=step)  /* compute hash */
    h = h ^ ((h<<5)+(h>>2)+cast(unsigned char, str[l1-1]));
  for (o = L->strt.hash[lmod(h, L->strt.size)];
       o != NULL;
       o = o->next) {
    TString *ts = o;
    if (h == ts->hash &&
        ts->len == l &&
        (memcmp(str, getstr(ts), l * sizeof(char)) == 0)) {
      //printf("string found: ");
      //fwrite(str,1,l,stdout);
      //printf("\n");
      return ts;
    }
  }
  //printf("string not found: ");
  //fwrite(str,1,l,stdout);
  //printf("\n");
  return newlstr(L, str, l, h);  /* not found; create a new string */
}


TString *luaS_new (lua_State *L, const char *str) {
  return luaS_newlstr(L, str, strlen(str));
}
TString * luaS_vstringf(lua_State * L, const char * fmt, va_list ap) {
	int N = 128;
	char stack_buf[128];
	char * buf = stack_buf;
	while(1) {
		int n = vsnprintf(buf, N, fmt, ap);
		if(n > -1 && n < N) {
			if(buf != stack_buf)
				free(buf);
			return luaS_newlstr(L,buf,n);
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
TString * luaS_stringf(lua_State * L, const char * fmt, ...) {
	va_list ap;
	va_start(ap, fmt);
	TString * ts = luaS_vstringf(L,fmt,ap);
	va_end(ap);
	return ts;
}
const char * luaS_cstringf(lua_State * L, const char * fmt, ...) {
	va_list ap;
	va_start(ap, fmt);
	TString * ts = luaS_vstringf(L,fmt,ap);
	va_end(ap);
	return getstr(ts);
}

