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
    TerraTarget() : nreferences(0), tm(NULL), ctx(NULL), external(NULL), next_unused_id(0) {}
    int nreferences;
    std::string Triple,CPU,Features;
    llvm::TargetMachine * tm;
    llvm::LLVMContext * ctx;
    llvm::Module * external; //module that holds IR for externally included things (from includec or linkllvm)
    size_t next_unused_id; //for creating names for dummy functions
};

struct TerraFunctionState { //compilation state
    llvm::Function * func;
    int index,lowlink; //for Tarjan's scc algorithm
    bool onstack;
};

struct TerraCompilationUnit {
    TerraCompilationUnit() : nreferences(0), optimize(false), T(NULL), C(NULL), M(NULL), mi(NULL), fpm(NULL), ee(NULL),jiteventlistener(NULL), Ty(NULL), CC(NULL), symbols(NULL), functioncount(0) {}
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
    int functioncount; // for assigning unique indexes to functions;
    std::vector<TerraFunctionState *>* tooptimize;
    const llvm::DataLayout & getDataLayout() {
        #if LLVM_VERSION <= 35
        return *M->getDataLayout();
        #else
        return M->getDataLayout();
        #endif
    }
};

struct terra_CompilerState {
    int nreferences;
    llvm::sys::MemoryBlock MB;
    llvm::DenseMap<const void *, TerraFunctionInfo> functioninfo;
};

#endif