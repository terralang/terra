#ifndef _tcompilerstate_h
#define _tcompilerstate_h

#include "llvmheaders.h"
#include "tinline.h"


struct TerraFunctionInfo {
    std::string name;
    void * addr;
    size_t size;
    llvm::JITEvent_EmittedFunctionDetails efd;
};
struct ImportedCModule {
    std::string livenessfunction;
    llvm::Module * M;
};
struct terra_CompilerState {
    llvm::Module * jitmodule;
    llvm::LLVMContext * ctx;
    llvm::ExecutionEngine * ee;
    llvm::JITEventListener * jiteventlistener;
    //llvm::PassManagerBase * fpm;
    //llvm::PassManager * cwrapperpm;
    llvm::TargetMachine * tm;
    const llvm::DataLayout * td;
    //ManualInliner * mi;
    llvm::DenseMap<const void *, TerraFunctionInfo> functioninfo;
    size_t next_unused_id; //for creating names for dummy functions
};

#endif