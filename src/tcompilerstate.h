#ifndef _tcompilerstate_h
#define _tcompilerstate_h

#include "llvm/DerivedTypes.h"
#include "llvm/ExecutionEngine/ExecutionEngine.h"
#include "llvm/ExecutionEngine/JIT.h"
#include "llvm/LLVMContext.h"
#include "llvm/Module.h"
#include "llvm/PassManager.h"
#include "llvm/Analysis/Verifier.h"
#include "llvm/Analysis/Passes.h"
#include "llvm/Target/TargetData.h"
#include "llvm/Transforms/Scalar.h"
#include "llvm/Support/IRBuilder.h"
#include "llvm/Support/TargetSelect.h"


struct terra_CompilerState {
    llvm::Module * m;
    llvm::LLVMContext * ctx;
    llvm::ExecutionEngine * ee;
    llvm::FunctionPassManager * fpm;
    size_t next_unused_id; //for creating names for dummy functions
};

#endif