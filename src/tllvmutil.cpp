/* See Copyright Notice in ../LICENSE.txt */

#include <stdio.h>

#include <iostream>

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

#if LLVM_VERSION >= 170
#include "llvm/Transforms/InstCombine/InstCombine.h"
#include "llvm/Transforms/IPO/GlobalDCE.h"
#include "llvm/Transforms/Scalar/AlignmentFromAssumptions.h"
#include "llvm/Transforms/Scalar/BDCE.h"
#include "llvm/Transforms/Scalar/CorrelatedValuePropagation.h"
#include "llvm/Transforms/Scalar/EarlyCSE.h"
#include "llvm/Transforms/Scalar/LICM.h"
#include "llvm/Transforms/Scalar/LoopLoadElimination.h"
#include "llvm/Transforms/Scalar/LoopUnrollAndJamPass.h"
#include "llvm/Transforms/Scalar/LoopUnrollPass.h"
#include "llvm/Transforms/Scalar/SCCP.h"
#include "llvm/Transforms/Scalar/SimpleLoopUnswitch.h"
#include "llvm/Transforms/Scalar/SimplifyCFG.h"
#include "llvm/Transforms/Scalar/SROA.h"
#include "llvm/Transforms/Scalar/WarnMissedTransforms.h"
#include "llvm/Transforms/Vectorize/LoopVectorize.h"
#include "llvm/Transforms/Vectorize/SLPVectorizer.h"
#include "llvm/Transforms/Vectorize/VectorCombine.h"
#endif

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
// Adapted from PassBuilder::addVectorPasses. LLVM doesn't expose this, and
// the function pipeline doesn't do vectorization by default, so we have to
// help ourselves here.
void addVectorPasses(PipelineTuningOptions PTO, OptimizationLevel Level,
                     FunctionPassManager &FPM, bool IsFullLTO, bool EnableUnrollAndJam,
                     bool ExtraVectorizerPasses) {
    FPM.addPass(LoopVectorizePass(
            LoopVectorizeOptions(!PTO.LoopInterleaving, !PTO.LoopVectorization)));

    // if (EnableInferAlignmentPass)
    //   FPM.addPass(InferAlignmentPass());
    if (IsFullLTO) {
        // The vectorizer may have significantly shortened a loop body; unroll
        // again. Unroll small loops to hide loop backedge latency and saturate any
        // parallel execution resources of an out-of-order processor. We also then
        // need to clean up redundancies and loop invariant code.
        // FIXME: It would be really good to use a loop-integrated instruction
        // combiner for cleanup here so that the unrolling and LICM can be pipelined
        // across the loop nests.
        // We do UnrollAndJam in a separate LPM to ensure it happens before unroll
        if (EnableUnrollAndJam && PTO.LoopUnrolling)
            FPM.addPass(createFunctionToLoopPassAdaptor(
                    LoopUnrollAndJamPass(Level.getSpeedupLevel())));
        FPM.addPass(LoopUnrollPass(LoopUnrollOptions(
                Level.getSpeedupLevel(), /*OnlyWhenForced=*/!PTO.LoopUnrolling,
                PTO.ForgetAllSCEVInLoopUnroll)));
        FPM.addPass(WarnMissedTransformationsPass());
        // Now that we are done with loop unrolling, be it either by LoopVectorizer,
        // or LoopUnroll passes, some variable-offset GEP's into alloca's could have
        // become constant-offset, thus enabling SROA and alloca promotion. Do so.
        // NOTE: we are very late in the pipeline, and we don't have any LICM
        // or SimplifyCFG passes scheduled after us, that would cleanup
        // the CFG mess this may created if allowed to modify CFG, so forbid that.
        FPM.addPass(SROAPass(SROAOptions::PreserveCFG));
    }

    if (!IsFullLTO) {
        // Eliminate loads by forwarding stores from the previous iteration to loads
        // of the current iteration.
        FPM.addPass(LoopLoadEliminationPass());
    }
    // Cleanup after the loop optimization passes.
    FPM.addPass(InstCombinePass());

    if (Level.getSpeedupLevel() > 1 && ExtraVectorizerPasses) {
        ExtraVectorPassManager ExtraPasses;
        // At higher optimization levels, try to clean up any runtime overlap and
        // alignment checks inserted by the vectorizer. We want to track correlated
        // runtime checks for two inner loops in the same outer loop, fold any
        // common computations, hoist loop-invariant aspects out of any outer loop,
        // and unswitch the runtime checks if possible. Once hoisted, we may have
        // dead (or speculatable) control flows or more combining opportunities.
        ExtraPasses.addPass(EarlyCSEPass());
        ExtraPasses.addPass(CorrelatedValuePropagationPass());
        ExtraPasses.addPass(InstCombinePass());
        LoopPassManager LPM;
        LPM.addPass(LICMPass(PTO.LicmMssaOptCap, PTO.LicmMssaNoAccForPromotionCap,
                             /*AllowSpeculation=*/true));
        LPM.addPass(
                SimpleLoopUnswitchPass(/* NonTrivial */ Level == OptimizationLevel::O3));
        ExtraPasses.addPass(
                createFunctionToLoopPassAdaptor(std::move(LPM), /*UseMemorySSA=*/true,
                                                /*UseBlockFrequencyInfo=*/true));
        ExtraPasses.addPass(
                SimplifyCFGPass(SimplifyCFGOptions().convertSwitchRangeToICmp(true)));
        ExtraPasses.addPass(InstCombinePass());
        FPM.addPass(std::move(ExtraPasses));
    }

    // Now that we've formed fast to execute loop structures, we do further
    // optimizations. These are run afterward as they might block doing complex
    // analyses and transforms such as what are needed for loop vectorization.

    // Cleanup after loop vectorization, etc. Simplification passes like CVP and
    // GVN, loop transforms, and others have already run, so it's now better to
    // convert to more optimized IR using more aggressive simplify CFG options.
    // The extra sinking transform can create larger basic blocks, so do this
    // before SLP vectorization.
    FPM.addPass(SimplifyCFGPass(SimplifyCFGOptions()
                                        .forwardSwitchCondToPhi(true)
                                        .convertSwitchRangeToICmp(true)
                                        .convertSwitchToLookupTable(true)
                                        .needCanonicalLoops(false)
                                        .hoistCommonInsts(true)
                                        .sinkCommonInsts(true)));

    if (IsFullLTO) {
        FPM.addPass(SCCPPass());
        FPM.addPass(InstCombinePass());
        FPM.addPass(BDCEPass());
    }

    // Optimize parallel scalar instruction chains into SIMD instructions.
    if (PTO.SLPVectorization) {
        FPM.addPass(SLPVectorizerPass());
        if (Level.getSpeedupLevel() > 1 && ExtraVectorizerPasses) {
            FPM.addPass(EarlyCSEPass());
        }
    }
    // Enhance/cleanup vector code.
    FPM.addPass(VectorCombinePass());

    if (!IsFullLTO) {
        FPM.addPass(InstCombinePass());
        // Unroll small loops to hide loop backedge latency and saturate any
        // parallel execution resources of an out-of-order processor. We also then
        // need to clean up redundancies and loop invariant code.
        // FIXME: It would be really good to use a loop-integrated instruction
        // combiner for cleanup here so that the unrolling and LICM can be pipelined
        // across the loop nests.
        // We do UnrollAndJam in a separate LPM to ensure it happens before unroll
        if (EnableUnrollAndJam && PTO.LoopUnrolling) {
            FPM.addPass(createFunctionToLoopPassAdaptor(
                    LoopUnrollAndJamPass(Level.getSpeedupLevel())));
        }
        FPM.addPass(LoopUnrollPass(LoopUnrollOptions(
                Level.getSpeedupLevel(), /*OnlyWhenForced=*/!PTO.LoopUnrolling,
                PTO.ForgetAllSCEVInLoopUnroll)));
        FPM.addPass(WarnMissedTransformationsPass());
        // Now that we are done with loop unrolling, be it either by LoopVectorizer,
        // or LoopUnroll passes, some variable-offset GEP's into alloca's could have
        // become constant-offset, thus enabling SROA and alloca promotion. Do so.
        // NOTE: we are very late in the pipeline, and we don't have any LICM
        // or SimplifyCFG passes scheduled after us, that would cleanup
        // the CFG mess this may created if allowed to modify CFG, so forbid that.
        FPM.addPass(SROAPass(SROAOptions::PreserveCFG));
    }

    // if (EnableInferAlignmentPass)
    //   FPM.addPass(InferAlignmentPass());
    FPM.addPass(InstCombinePass());

    // This is needed for two reasons:
    //   1. It works around problems that instcombine introduces, such as sinking
    //      expensive FP divides into loops containing multiplications using the
    //      divide result.
    //   2. It helps to clean up some loop-invariant code created by the loop
    //      unroll pass when IsFullLTO=false.
    FPM.addPass(createFunctionToLoopPassAdaptor(
            LICMPass(PTO.LicmMssaOptCap, PTO.LicmMssaNoAccForPromotionCap,
                     /*AllowSpeculation=*/true),
            /*UseMemorySSA=*/true, /*UseBlockFrequencyInfo=*/false));

    // Now that we've vectorized and unrolled loops, we may have more refined
    // alignment information, try to re-derive it here.
    FPM.addPass(AlignmentFromAssumptionsPass());
}

FunctionPassManager llvmutil_createoptimizationpasses(TargetMachine *TM,
                                                      LoopAnalysisManager &LAM,
                                                      FunctionAnalysisManager &FAM,
                                                      CGSCCAnalysisManager &CGAM,
                                                      ModuleAnalysisManager &MAM) {
    PipelineTuningOptions PTO;
    PTO.LoopVectorization = true;
    PTO.SLPVectorization = true;
    PassBuilder PB(TM, PTO);

    PB.registerModuleAnalyses(MAM);
    PB.registerCGSCCAnalyses(CGAM);
    PB.registerFunctionAnalyses(FAM);
    PB.registerLoopAnalyses(LAM);
    PB.crossRegisterProxies(LAM, FAM, CGAM, MAM);

    // FIXME (Elliott): is this the right pipeline to build? Not obvious if
    // it's equivalent to the old code path
    FunctionPassManager FPM = PB.buildFunctionSimplificationPipeline(
            OptimizationLevel::O3, ThinOrFullLTOPhase::None);

    addVectorPasses(PTO, OptimizationLevel::O3, FPM, /*IsFullLTO*/ false,
                    /*EnableUnrollAndJam*/ false, /*ExtraVectorizerPasses*/ true);

    // Debugging code for printing the set of pipelines
    /*
    {
        std::string buffer;
        llvm::raw_string_ostream rso(buffer);
        FPM.printPipeline(rso, [](auto a) { return a; });
        std::cout << rso.str() << std::endl;
    }
    */

    return FPM;
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

    CodeGenFileType ft = outputobjectfile ?
#if LLVM_VERSION < 180
                                          CGFT_ObjectFile
#else
                                          CodeGenFileType::ObjectFile
#endif
                                          :
#if LLVM_VERSION < 180
                                          CGFT_AssemblyFile
#else
                                          CodeGenFileType::AssemblyFile
#endif
            ;

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

    PipelineTuningOptions PTO;
    PTO.LoopVectorization = true;
    PTO.SLPVectorization = true;
    PassBuilder PB(TM, PTO);

    PB.registerModuleAnalyses(MAM);
    PB.registerCGSCCAnalyses(CGAM);
    PB.registerFunctionAnalyses(FAM);
    PB.registerLoopAnalyses(LAM);
    PB.crossRegisterProxies(LAM, FAM, CGAM, MAM);

    ModulePassManager MPM;
    MPM.addPass(VerifierPass());   // make sure we haven't messed stuff up yet
    MPM.addPass(GlobalDCEPass());  // run this early since anything not in the table of
                                   // exported functions is still in this module this
                                   // will remove dead functions
    MPM.addPass(PB.buildPerModuleDefaultPipeline(OptimizationLevel::O3));

    // Debugging code for printing the set of pipelines
    /*
    {
        std::string buffer;
        llvm::raw_string_ostream rso(buffer);
        MPM.printPipeline(rso, [](auto a) { return a; });
        std::cout << rso.str() << std::endl;
    }
    */

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
