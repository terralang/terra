#ifndef _tcompilerstate_h
#define _tcompilerstate_h

#include "llvmheaders.h"
#include "tinline.h"


struct TerraFunctionInfo {
    llvm::LLVMContext * ctx;
    std::string name;
    void * addr;
    size_t size;
    llvm::JITEvent_EmittedFunctionDetails efd;
};
class Types; struct CCallingConv; struct Obj;

struct TerraTarget {
    TerraTarget() : nreferences(0), tm(NULL), td(NULL), ctx(NULL), external(NULL), next_unused_id(0) {}
    int nreferences;
    std::string Triple,CPU,Features;
    llvm::TargetMachine * tm;
    const llvm::DataLayout * td;
    llvm::LLVMContext * ctx;
    llvm::Module * external; //module that holds IR for externally included things (from includec or linkllvm)
    size_t next_unused_id; //for creating names for dummy functions
};

struct TerraCompilationUnit {
    TerraCompilationUnit() : nreferences(0), optimize(false), T(NULL), C(NULL), M(NULL), mi(NULL), fpm(NULL), ee(NULL),jiteventlistener(NULL), Ty(NULL), CC(NULL), symbols(NULL) {}
    int nreferences;
    //configuration
    bool optimize;
    
    // LLVM state used in compiltion unit
    terra_State * T;
    terra_CompilerState * C;
    TerraTarget * TT;
    llvm::Module * M;
    ManualInliner * mi;
    FunctionPassManager * fpm;
    llvm::ExecutionEngine * ee;
    llvm::JITEventListener * jiteventlistener; //for reporting debug info
    // Temporary storage for objects that exist only during emitting functions
    Types * Ty;
    CCallingConv * CC;
    Obj * symbols;
    std::vector<llvm::Function *>* tooptimize;
};

struct terra_CompilerState {
    int nreferences;
    llvm::sys::MemoryBlock MB;
    llvm::DenseMap<const void *, TerraFunctionInfo> functioninfo;
};

#endif