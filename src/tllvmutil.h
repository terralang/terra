#ifndef tllvmutil_h
#define tllvmutil_h

#include "llvmheaders.h"

void llvmutil_addtargetspecificpasses(llvm::PassManagerBase *fpm,
                                      llvm::TargetMachine *tm);
void llvmutil_addoptimizationpasses(llvm::PassManagerBase *fpm);
extern "C" void llvmutil_disassemblefunction(void *data, size_t sz, size_t inst);
bool llvmutil_emitobjfile(llvm::Module *Mod, llvm::TargetMachine *TM,
                          bool outputobjectfile, emitobjfile_t &dest);

typedef bool (*llvmutil_Property)(llvm::GlobalValue *, void *);
llvm::Module *llvmutil_extractmodulewithproperties(
        llvm::StringRef DestName, llvm::Module *Src, llvm::GlobalValue **gvs, size_t N,
        llvmutil_Property copyGlobal, void *data, llvm::ValueToValueMapTy &VMap);
void llvmutil_copyfrommodule(llvm::Module *Dest, llvm::Module *Src,
                             llvm::GlobalValue **gvs, size_t N,
                             llvmutil_Property copyGlobal, void *data);
void llvmutil_optimizemodule(llvm::Module *M, llvm::TargetMachine *TM);
using std::error_code;
error_code llvmutil_createtemporaryfile(const llvm::Twine &Prefix, llvm::StringRef Suffix,
                                        llvm::SmallVectorImpl<char> &ResultPath);
int llvmutil_executeandwait(LLVM_PATH_TYPE program, const char **args, std::string *err);
#endif
