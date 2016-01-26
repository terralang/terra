#ifndef tinline_h
#define tinline_h

#include "llvmheaders.h"

class ManualInliner {
    llvm::CallGraphSCCPass * SI;
    llvm::CallGraph * CG;
    PassManager PM;
public:
    ManualInliner(llvm::TargetMachine * tm, llvm::Module * m);
    void run(std::vector<llvm::Function *>::iterator fbegin, std::vector<llvm::Function *>::iterator fend);
    void eraseFunction(llvm::Function * f);
};

#endif
