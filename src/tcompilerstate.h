#ifndef _tcompilerstate_h
#define _tcompilerstate_h

#include "llvmheaders.h"

struct terra_CompilerState {
    llvm::Module * m;
    llvm::LLVMContext * ctx;
    llvm::ExecutionEngine * ee;
    llvm::FunctionPassManager * fpm;
    llvm::TargetMachine * tm;
    size_t next_unused_id; //for creating names for dummy functions
};

#endif