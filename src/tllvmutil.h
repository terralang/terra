#ifndef tllvmutil_h
#define tllvmutil_h

#include "llvmheaders.h"

void llvmutil_addtargetspecificpasses(llvm::PassManagerBase * fpm, llvm::TargetMachine * tm);
void llvmutil_addoptimizationpasses(llvm::PassManagerBase * fpm);
extern "C" void llvmutil_disassemblefunction(void * data, size_t sz, size_t inst);
bool llvmutil_emitobjfile(llvm::Module * Mod, llvm::TargetMachine * TM, llvm::raw_ostream & dest, std::string * ErrorMessage);

#if LLVM_VERSION >= 33
typedef bool (*llvmutil_Property)(llvm::GlobalValue *,void*);
llvm::Module * llvmutil_extractmodulewithproperties(llvm::StringRef DestName, llvm::Module * Src, llvm::GlobalValue ** gvs, size_t N, llvmutil_Property copyGlobal, void * data, llvm::ValueToValueMapTy & VMap);
#endif

llvm::Module * llvmutil_extractmodule(llvm::Module * OrigMod, llvm::TargetMachine * TM, std::vector<llvm::GlobalValue*> * livevalues, std::vector<std::string> * symbolnames, bool internalizeandoptimize);

#if LLVM_VERSION >= 35
using std::error_code;
#else
using llvm::error_code;
#endif
error_code llvmutil_createtemporaryfile(const llvm::Twine &Prefix, llvm::StringRef Suffix, llvm::SmallVectorImpl<char> &ResultPath);
int llvmutil_executeandwait(LLVM_PATH_TYPE program, const char ** args, std::string * err);
#endif