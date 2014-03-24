#ifndef tinline_h
#define tinline_h

#include "llvmheaders.h"

class ManualInliner {
    llvm::CallGraphSCCPass * SI;
    llvm::CallGraph * CG;
    llvm::PassManager PM;
public:
    ManualInliner(llvm::TargetMachine * tm, llvm::Module * m);
    void run(std::vector<llvm::Function *> * fns);
    void eraseFunction(llvm::Function * f);
};

#endif
