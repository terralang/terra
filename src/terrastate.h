
#ifndef _terrastate_h
#define _terrastate_h

#include <stdint.h>
#include <stdarg.h>
#include <string.h>

struct terra_CompilerState;

typedef struct terra_State {
    struct lua_State * L;
    struct terra_CompilerState * C;
    int verbose;
//for parser
    int nCcalls;
    char tstring_table; //&tstring_table is used as the key into the lua registry that maps strings in Lua to TString objects for the parser
} terra_State;

//call this whenevern terra code is running within a lua call.
//this will be like calling 'error' from lua, and return the installed handler
void terra_reporterror(terra_State * T, const char * fmt, ...);

//call this when terra code is running outside of lua (e.g. in terra_init, or terra_dofile)
//it will push the error message to the lua stack
//the call is then responsibly for propagating the error to the caller of the terra function
void terra_pusherror(terra_State * T, const char * fmt, ...);
void terra_vpusherror(terra_State * T, const char * fmt, va_list ap);

#define DEBUG_ONLY(T) if((T)->verbose != 0)

#endif