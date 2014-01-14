#ifndef _tdebug_h
#define _tdebug_h

struct terra_State;
namespace llvm { struct JITMemoryManager; }

int terra_debuginit(struct terra_State * T, llvm::JITMemoryManager * JMM);

#endif
