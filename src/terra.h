#ifndef terra_h
#define terra_h
#include <stdint.h>
#include <stdarg.h>
#include <string.h>

struct terra_CompilerState;

typedef struct stringtable {
	struct TString **hash;
	uint32_t nuse;  /* number of elements */
	int size;
} stringtable;

typedef struct terra_State {
	struct lua_State * L;
	struct terra_CompilerState * C;
//for parser
	stringtable strt;
	int nCcalls;
} terra_State;
void terra_reporterror(terra_State * T, const char * fmt, ...);

terra_State * terra_newstate();
int terra_dofile(terra_State * T, const char * file);
#endif
