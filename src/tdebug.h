#ifndef _tdebug_h
#define _tdebug_h

struct terra_State;
namespace llvm { class JITMemoryManager; }

int terra_debuginit(struct terra_State * T);

#endif