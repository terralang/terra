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
        DisableUnrollLoops = false;
        UseGVNAfterVectorization = false;
        Vectorize = false;
    }
};

void llvmutil_addtargetspecificpasses(llvm::PassManagerBase * fpm, llvm::TargetMachine * tm);
void llvmutil_addoptimizationpasses(llvm::PassManagerBase * fpm, const OptInfo * oi);
extern "C" void llvmutil_disassemblefunction(void * data, size_t sz, size_t inst);
bool llvmutil_emitobjfile(llvm::Module * Mod, llvm::TargetMachine * TM, llvm::raw_ostream & dest, std::string * ErrorMessage);

#if defined(LLVM_3_3) ||  defined(LLVM_3_4)
typedef bool (*llvmutil_Property)(llvm::GlobalValue *,void*);
llvm::Module * llvmutil_extractmodulewithproperties(llvm::StringRef DestName, llvm::Module * Src, llvm::GlobalValue ** gvs, size_t N, llvmutil_Property copyGlobal, void * data, llvm::ValueToValueMapTy & VMap);
#endif

llvm::Module * llvmutil_extractmodule(llvm::Module * OrigMod, llvm::TargetMachine * TM, std::vector<llvm::Function*> * livefns, std::vector<std::string> * symbolnames);

//link src into dst, optimizing src in a way that won't delete its symbols before being linked to dst
//if optManager is NULL, then it won't perform optimizations,
//otherwisse optManager should be a pointer to a place to store a PassManager pointer.
//if this location is NULL, linkmodule will initialize a new PassManager to use for optimizations, otherwise
//it will re-use the pass manager already initialized in that location
bool llvmutil_linkmodule(llvm::Module * dst, llvm::Module * src, llvm::TargetMachine * TM, llvm::PassManager ** optManager, std::string * errmsg);


#endif