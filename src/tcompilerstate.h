#ifndef _tcompilerstate_h
#define _tcompilerstate_h

#include "llvmheaders.h"
#include "tinline.h"


struct TerraFunctionInfo {
    const llvm::Function * fn;
    void * addr;
    size_t size;
    llvm::JITEvent_EmittedFunctionDetails efd;
};
struct terra_CompilerState {
    llvm::Module * m;
    llvm::LLVMContext * ctx;
    llvm::ExecutionEngine * ee;
    llvm::JITEventListener * jiteventlistener;
    llvm::FunctionPassManager * fpm;
    llvm::PassManager * cwrapperpm;
    llvm::TargetMachine * tm;
    const llvm :: TARGETDATA() * td;
    llvm::ManualInliner * mi;
    llvm::DenseMap<const void *, TerraFunctionInfo> functioninfo;
    size_t next_unused_id; //for creating names for dummy functions
};

#endif