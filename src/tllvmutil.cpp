/* See Copyright Notice in ../LICENSE.txt */

#include <stdio.h>

#include "tllvmutil.h"

#include "llvm/Analysis/TargetLibraryInfo.h"
#include "llvm/MC/MCAsmInfo.h"
#include "llvm/MC/MCDisassembler/MCDisassembler.h"
#include "llvm/MC/MCInst.h"
#include "llvm/MC/MCInstPrinter.h"
#include "llvm/MC/MCInstrInfo.h"
#include "llvm/MC/MCRegisterInfo.h"
#include "llvm/MC/MCSubtargetInfo.h"
#include "llvm/MC/MCContext.h"
#ifndef _WIN32
#include <sys/wait.h>
#endif

using namespace llvm;

#if LLVM_VERSION < 170
void llvmutil_addtargetspecificpasses(PassManagerBase *fpm, TargetMachine *TM) {
    assert(TM && fpm);
    TargetLibraryInfoImpl TLII(TM->getTargetTriple());
    fpm->add(new TargetLibraryInfoWrapperPass(TLII));
    fpm->add(createTargetTransformInfoWrapperPass(TM->getTargetIRAnalysis()));
}

class PassManagerWrapper : public PassManagerBase {
public:
    PassManagerBase *PM;
    PassManagerWrapper(PassManagerBase *PM_) : PM(PM_) {}
    virtual void add(Pass *P) {
        if (P->getPotentialPassManagerType() > PMT_CallGraphPassManager ||
            P->getAsImmutablePass() != NULL)
            PM->add(P);
    }
};
void llvmutil_addoptimizationpasses(PassManagerBase *fpm) {
    PassManagerBuilder PMB;
    PMB.OptLevel = 3;
    PMB.SizeLevel = 0;
    PMB.LoopVectorize = true;
    PMB.SLPVectorize = true;

    PassManagerWrapper W(fpm);
    PMB.populateModulePassManager(W);
}
#else
FunctionPassManager llvmutil_createoptimizationpasses(TargetMachine *TM,
                                                      LoopAnalysisManager &LAM,
                                                      FunctionAnalysisManager &FAM,
                                                      CGSCCAnalysisManager &CGAM,
                                                      ModuleAnalysisManager &MAM) {
    PassBuilder PB(TM);

    PB.registerModuleAnalyses(MAM);
    PB.registerCGSCCAnalyses(CGAM);
    PB.registerFunctionAnalyses(FAM);
    PB.registerLoopAnalyses(LAM);
    PB.crossRegisterProxies(LAM, FAM, CGAM, MAM);

    // FIXME (Elliott): is this the right pipeline to build? Not obvious if
    // it's equivalent to the old code path
    return PB.buildFunctionSimplificationPipeline(OptimizationLevel::O3,
                                                  ThinOrFullLTOPhase::None);
}
#endif

void llvmutil_disassemblefunction(void *data, size_t numBytes, size_t numInst) {
    InitializeNativeTargetDisassembler();
    std::string Error;
    std::string TripleName = llvm::sys::getProcessTriple();
    std::string CPU = llvm::sys::getHostCPUName().str();

    const Target *TheTarget = TargetRegistry::lookupTarget(TripleName, Error);
    assert(TheTarget && "Unable to create target!");
    const MCAsmInfo *MAI = TheTarget->createMCAsmInfo(
            *TheTarget->createMCRegInfo(TripleName), TripleName, MCTargetOptions());
    assert(MAI && "Unable to create target asm info!");
    const MCInstrInfo *MII = TheTarget->createMCInstrInfo();
    assert(MII && "Unable to create target instruction info!");
    const MCRegisterInfo *MRI = TheTarget->createMCRegInfo(TripleName);
    assert(MRI && "Unable to create target register info!");

    std::string FeaturesStr;
    const MCSubtargetInfo *STI =
            TheTarget->createMCSubtargetInfo(TripleName, CPU, FeaturesStr);
    assert(STI && "Unable to create subtarget info!");

#if LLVM_VERSION < 130
    MCContext Ctx(MAI, MRI, NULL);
#else
    llvm::Triple TRI(llvm::sys::getProcessTriple());
    MCContext Ctx(TRI, MAI, MRI, NULL);
#endif

    MCDisassembler *DisAsm = TheTarget->createMCDisassembler(*STI, Ctx);

    assert(DisAsm && "Unable to create disassembler!");

    int AsmPrinterVariant = MAI->getAssemblerDialect();
    MCInstPrinter *IP = TheTarget->createMCInstPrinter(
            Triple(TripleName), AsmPrinterVariant, *MAI, *MII, *MRI);
    assert(IP && "Unable to create instruction printer!");

    ArrayRef<uint8_t> Bytes((uint8_t *)data, numBytes);

    uint64_t addr = (uint64_t)data;
    uint64_t Size;
    fflush(stdout);
    raw_fd_ostream Out(fileno(stdout), false);
    for (size_t i = 0, b = 0; b < numBytes || i < numInst; i++, b += Size) {
        MCInst Inst;
        MCDisassembler::DecodeStatus S =
                DisAsm->getInstruction(Inst, Size, Bytes.slice(b), addr + b, Out);
        if (MCDisassembler::Fail == S || MCDisassembler::SoftFail == S) break;
        Out << (void *)((uintptr_t)data + b) << "(+" << b << ")"
            << ":\t";
        IP->printInst(&Inst, addr + b, "", *STI, Out);
        Out << "\n";
    }
    Out.flush();
    delete MAI;
    delete MRI;
    delete STI;
    delete MII;
    delete DisAsm;
    delete IP;
}

// adapted from LLVM's C interface "LLVMTargetMachineEmitToFile"
bool llvmutil_emitobjfile(Module *Mod, TargetMachine *TM, bool outputobjectfile,
                          emitobjfile_t &dest) {
    legacy::PassManager pass;
#if LLVM_VERSION < 170
    llvmutil_addtargetspecificpasses(&pass, TM);
#else
    Mod->setDataLayout(TM->createDataLayout());
#endif

    CodeGenFileType ft = outputobjectfile ? CGFT_ObjectFile : CGFT_AssemblyFile;

    emitobjfile_t &destf = dest;

    if (TM->addPassesToEmitFile(pass, destf, nullptr, ft)) {
        return true;
    }

    pass.run(*Mod);

    destf.flush();
    dest.flush();

    return false;
}

struct CopyConnectedComponent : public ValueMaterializer {
    Module *dest;
    Module *src;
    llvmutil_Property copyGlobal;
    void *data;
    ValueToValueMapTy &VMap;

    CopyConnectedComponent(Module *dest_, Module *src_, llvmutil_Property copyGlobal_,
                           void *data_, ValueToValueMapTy &VMap_)
            : dest(dest_),
              src(src_),
              copyGlobal(copyGlobal_),
              data(data_),
              VMap(VMap_),
              DI(NULL) {}
    bool needsFreshlyNamedConstant(GlobalVariable *GV, GlobalVariable *newGV) {
        if (GV->isConstant() && GV->hasPrivateLinkage() &&
            GV->hasAtLeastLocalUnnamedAddr()) {  // this is a candidate constant
            return !newGV->isConstant() ||
                   newGV->getInitializer() !=
                           GV->getInitializer();  // it is not equal to its target
        }
        return false;
    }
    virtual Value *materialize(Value *V) override {
        if (Function *fn = dyn_cast<Function>(V)) {
            assert(fn->getParent() == src);
            Function *newfn = dest->getFunction(fn->getName());
            if (!newfn) {
                newfn = Function::Create(fn->getFunctionType(), fn->getLinkage(),
                                         fn->getName(), dest);
                newfn->copyAttributesFrom(fn);
                // copyAttributesFrom does not copy comdats
                newfn->setComdat(fn->getComdat());
            }
            if (!fn->isDeclaration() && newfn->isDeclaration() && copyGlobal(fn, data)) {
                for (Function::arg_iterator II = newfn->arg_begin(), I = fn->arg_begin(),
                                            E = fn->arg_end();
                     I != E; ++I, ++II) {
                    II->setName(I->getName());
                    VMap[&*I] = &*II;
                }
                VMap[fn] = newfn;
                SmallVector<ReturnInst *, 8> Returns;
#if LLVM_VERSION < 130
                CloneFunctionInto(newfn, fn, VMap, true, Returns, "", NULL, NULL, this);
#else
                CloneFunctionInto(newfn, fn, VMap,
                                  CloneFunctionChangeType::DifferentModule, Returns, "",
                                  NULL, NULL, this);
#endif
                DISubprogram *SP = fn->getSubprogram();

                Function *F = cast<Function>(MapValue(fn, VMap, RF_None, NULL, this));

                if (SP) {
                    F->setSubprogram(DI->createFunction(
                            SP->getScope(), SP->getName(), SP->getLinkageName(),
                            DI->createFile(SP->getFilename(), SP->getDirectory()),
                            SP->getLine(), SP->getType(), SP->getScopeLine(),
                            SP->getFlags(), SP->getSPFlags(), SP->getTemplateParams(),
                            SP->getDeclaration(), SP->getThrownTypes()));
                }
            } else {
                newfn->setLinkage(GlobalValue::ExternalLinkage);
            }
            return newfn;
        } else if (GlobalVariable *GV = dyn_cast<GlobalVariable>(V)) {
            GlobalVariable *newGV = dest->getGlobalVariable(GV->getName(), true);
            if (!newGV || needsFreshlyNamedConstant(GV, newGV)) {
                newGV = new GlobalVariable(*dest, GV->getValueType(), GV->isConstant(),
                                           GV->getLinkage(), NULL, GV->getName(), NULL,
                                           GlobalVariable::NotThreadLocal,
                                           GV->getType()->getAddressSpace());
                newGV->copyAttributesFrom(GV);
                // copyAttributesFrom does not copy comdats
                newGV->setComdat(GV->getComdat());
                if (!GV->isDeclaration()) {
                    if (!copyGlobal(GV, data)) {
                        newGV->setLinkage(GlobalValue::ExternalLinkage);
                    } else if (GV->hasInitializer()) {
                        Value *C =
                                MapValue(GV->getInitializer(), VMap, RF_None, NULL, this);
                        newGV->setInitializer(cast<Constant>(C));
                    }
                }
            }
            return newGV;
        } else
            return materializeValueForMetadata(V);
    }
    DIBuilder *DI;
    DICompileUnit *NCU;
    void CopyDebugMetadata() {
        if (NamedMDNode *NMD = src->getNamedMetadata("llvm.module.flags")) {
            NamedMDNode *New = dest->getOrInsertNamedMetadata(NMD->getName());
            for (unsigned i = 0; i < NMD->getNumOperands(); i++) {
                New->addOperand(MapMetadata(NMD->getOperand(i), VMap));
            }
        }

        NCU = NULL;
        // for (DICompileUnit *CU : src->debug_compile_units()) {
        if (src->debug_compile_units_begin() != src->debug_compile_units_end()) {
            DICompileUnit *CU = *src->debug_compile_units_begin();

            if (DI == NULL) DI = new DIBuilder(*dest);

            if (CU) {
                NCU = DI->createCompileUnit(
                        CU->getSourceLanguage(), CU->getFile(), CU->getProducer(),
                        CU->isOptimized(), CU->getFlags(), CU->getRuntimeVersion(),
                        CU->getSplitDebugFilename(), CU->getEmissionKind(),
                        CU->getDWOId(), CU->getSplitDebugInlining(),
                        CU->getDebugInfoForProfiling(), CU->getNameTableKind(),
                        CU->getRangesBaseAddress());
            }
        }
    }

    Value *materializeValueForMetadata(Value *V) {
        if (auto *MDV = dyn_cast<MetadataAsValue>(V)) {
            Metadata *MDraw = MDV->getMetadata();
            MDNode *MD = dyn_cast<MDNode>(MDraw);
            DISubprogram *SP = getDISubprogram(MD);
            if (MD != NULL && DI != NULL && SP != NULL) {
                {
                    DISubprogram *NSP = DI->createFunction(
                            SP->getScope(), SP->getName(), SP->getLinkageName(),
                            DI->createFile(SP->getFilename(), SP->getDirectory()),
                            SP->getLine(), SP->getType(), SP->getScopeLine(),
                            SP->getFlags(), SP->getSPFlags(), SP->getTemplateParams(),
                            SP->getDeclaration(), SP->getThrownTypes());

                    Function *newfn = dest->getFunction(SP->getName());
                    if (!newfn) newfn = dest->getFunction(SP->getLinkageName());
                    if (newfn) {
                        newfn->setSubprogram(NSP);
                    }

                    return MetadataAsValue::get(dest->getContext(), NSP);
                }
                /* fallthrough */
            }
            /* fallthrough */
        }
        return NULL;
    }
    void finalize() {
        if (DI) {
            DI->finalize();
            delete DI;
            DI = NULL;
        }
    }
};

llvm::Module *llvmutil_extractmodulewithproperties(
        llvm::StringRef DestName, llvm::Module *Src, llvm::GlobalValue **gvs, size_t N,
        llvmutil_Property copyGlobal, void *data, llvm::ValueToValueMapTy &VMap) {
    Module *Dest = new Module(DestName, Src->getContext());
    Dest->setTargetTriple(Src->getTargetTriple());
    CopyConnectedComponent cp(Dest, Src, copyGlobal, data, VMap);
    cp.CopyDebugMetadata();
    for (size_t i = 0; i < N; i++) MapValue(gvs[i], VMap, RF_None, NULL, &cp);
    cp.finalize();
    return Dest;
}
void llvmutil_copyfrommodule(llvm::Module *Dest, llvm::Module *Src,
                             llvm::GlobalValue **gvs, size_t N,
                             llvmutil_Property copyGlobal, void *data) {
    llvm::ValueToValueMapTy VMap;
    CopyConnectedComponent cp(Dest, Src, copyGlobal, data, VMap);
    for (size_t i = 0; i < N; i++) MapValue(gvs[i], VMap, RF_None, NULL, &cp);
}

void llvmutil_optimizemodule(Module *M, TargetMachine *TM) {
#if LLVM_VERSION < 170
    PassManagerT MPM;
    llvmutil_addtargetspecificpasses(&MPM, TM);

    MPM.add(createVerifierPass());   // make sure we haven't messed stuff up yet
    MPM.add(createGlobalDCEPass());  // run this early since anything not in the table of
                                     // exported functions is still in this module this
                                     // will remove dead functions

    PassManagerBuilder PMB;
    PMB.OptLevel = 3;
    PMB.SizeLevel = 0;
    PMB.Inliner = createFunctionInliningPass(PMB.OptLevel, 0, false);

    PMB.LoopVectorize = true;
    PMB.SLPVectorize = true;

    PMB.populateModulePassManager(MPM);

    MPM.run(*M);
#else
    LoopAnalysisManager LAM;
    FunctionAnalysisManager FAM;
    CGSCCAnalysisManager CGAM;
    ModuleAnalysisManager MAM;

    PassBuilder PB(TM);

    PB.registerModuleAnalyses(MAM);
    PB.registerCGSCCAnalyses(CGAM);
    PB.registerFunctionAnalyses(FAM);
    PB.registerLoopAnalyses(LAM);
    PB.crossRegisterProxies(LAM, FAM, CGAM, MAM);

    ModulePassManager MPM = PB.buildPerModuleDefaultPipeline(OptimizationLevel::O3);

    MPM.run(*M, MAM);
#endif
}

error_code llvmutil_createtemporaryfile(const Twine &Prefix, StringRef Suffix,
                                        SmallVectorImpl<char> &ResultPath) {
    return sys::fs::createTemporaryFile(Prefix, Suffix, ResultPath);
}

int llvmutil_executeandwait(LLVM_PATH_TYPE program, const char **args, std::string *err) {
    bool executionFailed = false;
    llvm::sys::ProcessInfo Info =
            llvm::sys::ExecuteNoWait(program, llvm::toStringRefArray(args),
#if LLVM_VERSION < 160
                                     llvm::None,
#else
                                     std::nullopt,
#endif
                                     {}, 0, err, &executionFailed);
    if (executionFailed) return -1;
#ifndef _WIN32
    // WAR for llvm bug (http://llvm.org/bugs/show_bug.cgi?id=18869)
    pid_t pid;
    int status;
    do {
        pid = waitpid(Info.Pid, &status, 0);
    } while (pid == -1 && errno == EINTR);
    if (pid == -1) {
        *err = strerror(errno);
        return -1;
    } else {
        return WEXITSTATUS(status);
    }
#else
    return llvm::sys::Wait(Info, 0, true, err).ReturnCode;
#endif
}
