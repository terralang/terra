#ifndef tinline_h
#define tinline_h

#include "llvmheaders.h"

#if LLVM_VERSION >= 170
#include "llvm/Analysis/InlineCost.h"
#endif

// Terra compiles functions one strongly-connected-component at a time, so it
// cannot use LLVM's module-at-a-time inliner in the JIT. Instead it drives an
// inliner by hand over each SCC as that SCC is completed (see EmitFunction in
// tcompiler.cpp). Callees are always emitted and optimized before their
// callers, so this reproduces the bottom-up order LLVM's own inliner uses.
class ManualInliner {
#if LLVM_VERSION < 170
    llvm::CallGraphSCCPass *SI;
    llvm::CallGraph *CG;
    PassManager PM;

public:
    ManualInliner(llvm::TargetMachine *tm, llvm::Module *m);
    void eraseFunction(llvm::Function *f);
#else
    llvm::Module *M;
    llvm::FunctionAnalysisManager *FAM;
    llvm::ModuleAnalysisManager *MAM;
    llvm::InlineParams Params;

public:
    ManualInliner(llvm::TargetMachine *tm, llvm::Module *m,
                  llvm::FunctionAnalysisManager &fam, llvm::ModuleAnalysisManager &mam);
#endif
    void run(std::vector<llvm::Function *>::iterator fbegin,
             std::vector<llvm::Function *>::iterator fend);
};

#endif
