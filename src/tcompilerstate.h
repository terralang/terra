#ifndef _tcompilerstate_h
#define _tcompilerstate_h

#include "llvmheaders.h"
#include "tinline.h"

#include <memory>
#include <string>
#include <vector>

// One row of a line table, at the address the code was actually loaded at. A
// zero line means no source line for this address, which covers both the end of
// a sequence and a row whose line or file the DWARF did not give.
struct TerraLineInfo {
    uint64_t addr;
    uint32_t line;
    uint32_t fileid;  // indexes TerraDebugInfo::filenames
};

// The line table of one JIT'd object, shared by every function in it. It is
// read when the object loads rather than when a frame is printed, because
// printing happens from a signal handler, where parsing DWARF would allocate.
struct TerraDebugInfo {
    std::vector<TerraLineInfo> lines;  // sorted by addr
    std::vector<std::string> filenames;
};

struct TerraFunctionInfo {
    std::string name;
    void *addr;
    size_t size;
    std::shared_ptr<TerraDebugInfo> debug;
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
              mi(NULL),
              fpm(NULL),
              ee(NULL),
              jiteventlistener(NULL),
              Ty(NULL),
              CC(NULL),
              symbols(NULL),
              functioncount(0) {}
    int nreferences;
    // configuration
    bool optimize;
    llvm::FastMathFlags fastmath;

    // LLVM state used in compiltion unit
    terra_State *T;
    terra_CompilerState *C;
    TerraTarget *TT;
    llvm::Module *M;
    ManualInliner *mi;
#if LLVM_VERSION >= 170
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
    int nreferences = 0;
    int debug = 0;
    llvm::sys::MemoryBlock MB;
    llvm::DenseMap<const void *, TerraFunctionInfo> functioninfo;
};

#endif
