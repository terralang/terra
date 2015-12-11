
#ifndef _terrastate_h
#define _terrastate_h

#include <stdint.h>
#include <stdarg.h>
#include <string.h>
#include "terra.h"

struct terra_CompilerState;
struct terra_CUDAState;

typedef struct terra_State {
    struct lua_State * L;
    struct terra_CompilerState * C;
    struct terra_CUDAState * cuda;
    terra_Options options;
//for parser
    int nCcalls;
    char tstring_table; //&tstring_table is used as the key into the lua registry that maps strings in Lua to TString objects for the parser
    size_t numlivefunctions; //number of terra functions that are live in the system, + 1 if terra_free has not been called
                            //used to track when it is safe to delete the terra_State object.
} terra_State;

//call this whenevern terra code is running within a lua call.
//this will be like calling 'error' from lua, and return the installed handler
void terra_reporterror(terra_State * T, const char * fmt, ...);

//call this when terra code is running outside of lua (e.g. in terra_init, or terra_dofile)
//it will push the error message to the lua stack
//the call is then responsibly for propagating the error to the caller of the terra function
void terra_pusherror(terra_State * T, const char * fmt, ...);
void terra_vpusherror(terra_State * T, const char * fmt, va_list ap);
int terra_loadandrunbytecodes(lua_State * L, const unsigned char * bytecodes, size_t size, const char * name);
terra_State * terra_getstate(lua_State * L, int closureindex);
#define VERBOSE_ONLY(T) if((T)->options.verbose != 0)
#define DEBUG_ONLY(T) if((T)->options.debug != 0)

//definition in tclanginternalizedheaders.cpp
void terra_registerinternalizedfiles(lua_State * L, int terratable);

#endif
