#ifndef terra_h
#define terra_h
#include <stdint.h>
#include <stdarg.h>
#include <string.h>

struct terra_CompilerState;

typedef struct terra_State {
    struct lua_State * L;
    struct terra_CompilerState * C;
//for parser
    int nCcalls;
    char tstring_table; //&tstring_table is used as the key into the lua registry that maps strings in Lua to TString objects for the parser
} terra_State;

void terra_reporterror(terra_State * T, const char * fmt, ...);

terra_State * terra_newstate();
int terra_dofile(terra_State * T, const char * file);
#endif
