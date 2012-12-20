#ifndef tllvmutil_h
#define tllvmutil_h

#include "llvmheaders.h"

struct OptInfo {
    int OptLevel;
    int SizeLevel;
    bool DisableUnitAtATime;
    bool DisableSimplifyLibCalls;
    bool DisableUnrollLoops;
    bool Vectorize;
    bool UseGVNAfterVectorization;
    OptInfo() {
        OptLevel = 3;
        SizeLevel = 0;
        DisableSimplifyLibCalls = false;
        DisableUnrollLoops = true;
        UseGVNAfterVectorization = false;
        Vectorize = false;
    }
};

void llvmutil_addtargetspecificpasses(llvm::PassManagerBase * fpm, llvm::TargetMachine * tm);
void llvmutil_addoptimizationpasses(llvm::FunctionPassManager * fpm, const OptInfo * oi);
void llvmutil_disassemblefunction(void * data, size_t sz);
bool llvmutil_emitobjfile(llvm::Module * Mod, llvm::TargetMachine * TM, const char * Filename, std::string * ErrorMessage);
#endif