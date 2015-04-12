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
class Types; struct CCallingConv; struct Obj;
struct TerraCompilationUnit {
    TerraCompilationUnit() : T(NULL), M(NULL), mi(NULL), fpm(NULL), tm(NULL), td(NULL), ee(NULL),jiteventlistener(NULL), Ty(NULL), CC(NULL), symbols(NULL) {}
    terra_State * T;
    std::string Triple,CPU;
    llvm::Module * M;
    ManualInliner * mi;
    llvm::FunctionPassManager * fpm;
    llvm::TargetMachine * tm;
    const llvm::DataLayout * td;
    std::string livenessfunction; //used in imported C code to find the LLVM types that correspond to the C types imported
    llvm::ExecutionEngine * ee;
    llvm::JITEventListener * jiteventlistener; //for reporting debug info
    // Temporary storage for objects that exist only during emitting functions
    Types * Ty;
    CCallingConv * CC;
    Obj * symbols;
    std::vector<llvm::Function *>* tooptimize;
};

struct terra_CompilerState {
    llvm::LLVMContext * ctx;
    llvm::JITMemoryManager * JMM;
    llvm::DenseMap<const void *, TerraFunctionInfo> functioninfo;
    size_t next_unused_id; //for creating names for dummy functions
};

#endif