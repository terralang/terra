/*
** $Id: lparser.h,v 1.69 2011/07/27 18:09:01 roberto Exp $
** Lua Parser
** See Copyright Notice in lua.h
*/

#ifndef lparser_h
#define lparser_h

#include "putil.h"
#include "lobject.h"
#include "lzio.h"


/*
** Expression descriptor
*/

typedef enum {
  ECALL,
  EVOID
} expkind;

typedef struct expdesc {
  expkind k;
} expdesc;

/* control of blocks */
struct BlockCnt;  /* defined in lparser.c */

typedef struct Proto {
	int linedefined;
	int lastlinedefined;
	int is_vararg;
	TString * source;
} Proto;

/* state needed to generate code for a given function */
typedef struct FuncState {
  Proto f;  /* current function header */
  struct FuncState *prev;  /* enclosing function */
  struct LexState *ls;  /* lexical state */
  struct BlockCnt *bl;  /* chain of current blocks */
} FuncState;


LUAI_FUNC void luaY_parser (lua_State *L, ZIO *z, Mbuffer *buff, const char *name, int firstchar);


#endif
