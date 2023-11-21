#ifndef _tcompilerstate_h
#define _tcompilerstate_h

#include "llvmheaders.h"
#if LLVM_VERSION < 170
// FIXME (Elliott): need to restore the manual inliner in LLVM 17
#include "tinline.h"
#endif

struct TerraFunctionInfo {
    llvm::LLVMContext *ctx;
    std::string name;
    void *addr;
    size_t size;
};
class Types;
struct CCallingConv;
struct Obj;

struct TerraTarget {
    TerraTarget()
            : nreferences(0), tm(NULL), ctx(NULL), external(NULL), next_unused_id(0) {}
    int nreferences;
    std::string Triple, CPU, Features;
    llvm::TargetMachine *tm;
    llvm::LLVMContext *ctx;
    llvm::Module *external;  // module that holds IR for externally included things (from
                             // includec or linkllvm)
    size_t next_unused_id;   // for creating names for dummy functions
    size_t id;
};

struct TerraFunctionState {  // compilation state
    llvm::Function *func;
    int index, lowlink;  // for Tarjan's scc algorithm
    bool onstack;
};

struct TerraCompilationUnit {
    TerraCompilationUnit()
            : nreferences(0),
              optimize(false),
              fastmath(),
              T(NULL),
              C(NULL),
              M(NULL),
#if LLVM_VERSION < 170
              // FIXME (Elliott): need to restore the manual inliner in LLVM 17
              mi(NULL),
#endif
              fpm(NULL),
              ee(NULL),
              jiteventlistener(NULL),
              Ty(NULL),
              CC(NULL),
              symbols(NULL),
              functioncount(0) {
    }
    int nreferences;
    // configuration
    bool optimize;
    llvm::FastMathFlags fastmath;

    // LLVM state used in compiltion unit
    terra_State *T;
    terra_CompilerState *C;
    TerraTarget *TT;
    llvm::Module *M;
#if LLVM_VERSION < 170
    // FIXME (Elliott): need to restore the manual inliner in LLVM 17
    ManualInliner *mi;
#else
    llvm::LoopAnalysisManager lam;
    llvm::FunctionAnalysisManager fam;
    llvm::CGSCCAnalysisManager cgam;
    llvm::ModuleAnalysisManager mam;
#endif
    FunctionPassManager *fpm;
    llvm::ExecutionEngine *ee;
    llvm::JITEventListener *jiteventlistener;  // for reporting debug info
    // Temporary storage for objects that exist only during emitting functions
    Types *Ty;
    CCallingConv *CC;
    Obj *symbols;
    int functioncount;  // for assigning unique indexes to functions;
    std::vector<TerraFunctionState *> *tooptimize;
    const llvm::DataLayout &getDataLayout() { return M->getDataLayout(); }
};

struct terra_CompilerState {
    int nreferences;
    llvm::sys::MemoryBlock MB;
    llvm::DenseMap<const void *, TerraFunctionInfo> functioninfo;
};

#endif
