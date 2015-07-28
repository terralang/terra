#ifndef _tcompiler_h
#define _tcompiler_h

struct terra_State;
struct terra_CompilerState;
int terra_compilerinit(struct terra_State * T);
int terra_compilerfree(struct terra_CompilerState * T);

#endif