/* See Copyright Notice in ../LICENSE.txt */

#include <stdio.h>

#include "tllvmutil.h"
#include "llvm/Target/TargetLibraryInfo.h"

#include "llvm/MC/MCAsmInfo.h"
#include "llvm/MC/MCDisassembler.h"
#include "llvm/MC/MCInst.h"
#include "llvm/MC/MCInstPrinter.h"
#include "llvm/MC/MCInstrInfo.h"
#include "llvm/MC/MCRegisterInfo.h"
#include "llvm/MC/MCSubtargetInfo.h"
#include "llvm/Support/MemoryObject.h"

using namespace llvm;

void llvmutil_addtargetspecificpasses(PassManagerBase * fpm, TargetMachine * TM) {
    TargetLibraryInfo * TLI = new TargetLibraryInfo(Triple(TM->getTargetTriple()));
#if defined(TERRA_ENABLE_CUDA) && defined(__APPLE__)
    //currently there isn't a seperate pathway for optimization when code will be running on CUDA
    //so we need to avoid generating functions that don't exist there like memset_pattern16 for all code
    //we only do this if cuda is enabled on OSX where the problem occurs to avoid slowing down other code
    TLI->setUnavailable(LibFunc::memset_pattern16);
#endif
    fpm->add(TLI);
    fpm->add(new TARGETDATA()(*TM->TARGETDATA(get)()));
#ifdef LLVM_3_2
    fpm->add(new TargetTransformInfo(TM->getScalarTargetTransformInfo(),
                                     TM->getVectorTargetTransformInfo()));
#elif LLVM_3_3
    TM->addAnalysisPasses(*fpm);
#endif
}


void llvmutil_addoptimizationpasses(PassManagerBase * fpm, const OptInfo * oi) {
    //These passes are passes from PassManagerBuilder adapted to work a function at at time
    //inlining is handled as a preprocessing step before this gets called
    
    //look here: http://lists.cs.uiuc.edu/pipermail/llvmdev/2011-December/045867.html

    // If all optimizations are disabled, just run the always-inline pass. (TODO: actually run the always-inline pass and disable other inlining)
    if(oi->OptLevel == 0)
        return;
    
    //fpm->add(createTypeBasedAliasAnalysisPass()); //TODO: emit metadata so that this pass does something
    fpm->add(createBasicAliasAnalysisPass());
    
    
    
    // Start of CallGraph SCC passes. (
    //if (!DisableUnitAtATime)
    //    fpm->add(createFunctionAttrsPass());       // Set readonly/readnone attrs (TODO: can we run this if we modify it to work with JIT?)
    
    //if (OptLevel > 2)
    //    fpm->add(createArgumentPromotionPass());   // Scalarize uninlined fn args (TODO: can we run this if we modify it to work wit ==h JIT?)

    // Start of function pass.
    // Break up aggregate allocas, using SSAUpdater.
    fpm->add(createScalarReplAggregatesPass(-1, false));
    fpm->add(createEarlyCSEPass());              // Catch trivial redundancies
    
#ifndef LLVM_3_4
    if (!oi->DisableSimplifyLibCalls)
        fpm->add(createSimplifyLibCallsPass());    // Library Call Optimizations
#endif
    
    fpm->add(createJumpThreadingPass());         // Thread jumps.
    fpm->add(createCorrelatedValuePropagationPass()); // Propagate conditionals
    fpm->add(createCFGSimplificationPass());     // Merge & remove BBs
    fpm->add(createInstructionCombiningPass());  // Combine silly seq's

    fpm->add(createTailCallEliminationPass());   // Eliminate tail calls
    fpm->add(createCFGSimplificationPass());     // Merge & remove BBs
    fpm->add(createReassociatePass());           // Reassociate expressions
    fpm->add(createLoopRotatePass());            // Rotate Loop
    fpm->add(createLICMPass());                  // Hoist loop invariants
    fpm->add(createLoopUnswitchPass(oi->SizeLevel || oi->OptLevel < 3));
    fpm->add(createInstructionCombiningPass());
    fpm->add(createIndVarSimplifyPass());        // Canonicalize indvars
    fpm->add(createLoopIdiomPass());             // Recognize idioms like memset.
    fpm->add(createLoopDeletionPass());          // Delete dead loops
    if (!oi->DisableUnrollLoops)
        fpm->add(createLoopUnrollPass());          // Unroll small loops
    
    if (oi->OptLevel > 1)
        fpm->add(createGVNPass());                 // Remove redundancies
    fpm->add(createMemCpyOptPass());             // Remove memcpy / form memset
    fpm->add(createSCCPPass());                  // Constant prop with SCCP

    // Run instcombine after redundancy elimination to exploit opportunities
    // opened up by them.
    fpm->add(createInstructionCombiningPass());
    fpm->add(createJumpThreadingPass());         // Thread jumps
    fpm->add(createCorrelatedValuePropagationPass());
    fpm->add(createDeadStoreEliminationPass());  // Delete dead stores

    if (oi->Vectorize) {
        fpm->add(createBBVectorizePass());
        fpm->add(createInstructionCombiningPass());
        if (oi->OptLevel > 1 && oi->UseGVNAfterVectorization)
            fpm->add(createGVNPass());                   // Remove redundancies
        else
            fpm->add(createEarlyCSEPass());              // Catch trivial redundancies
    }
    fpm->add(createAggressiveDCEPass());         // Delete dead instructions
    fpm->add(createCFGSimplificationPass());     // Merge & remove BBs
    fpm->add(createInstructionCombiningPass());  // Clean up after everything.
}


struct SimpleMemoryObject : public MemoryObject {
  uint8_t *Bytes;
  uint64_t Size;
  uint64_t getBase() const { return 0; }
  uint64_t getExtent() const { return Size; }
  int readByte(uint64_t Addr, uint8_t *Byte) const {
    *Byte = Bytes[Addr];
    return 0;
  }
};

void llvmutil_disassemblefunction(void * data, size_t numBytes, size_t numInst) {
    InitializeNativeTargetDisassembler();
    std::string Error;
    std::string TripleName = llvm::sys::getDefaultTargetTriple();
    const Target *TheTarget = TargetRegistry::lookupTarget(TripleName, Error);
    assert(TheTarget && "Unable to create target!");
    const MCAsmInfo *MAI = TheTarget->createMCAsmInfo(
#ifdef LLVM_3_4
            *TheTarget->createMCRegInfo(TripleName),
#endif
            TripleName);
    assert(MAI && "Unable to create target asm info!");
    const MCInstrInfo *MII = TheTarget->createMCInstrInfo();
    assert(MII && "Unable to create target instruction info!");
    const MCRegisterInfo *MRI = TheTarget->createMCRegInfo(TripleName);
    assert(MRI && "Unable to create target register info!");

    std::string FeaturesStr;
    std::string CPU;
    const MCSubtargetInfo *STI = TheTarget->createMCSubtargetInfo(TripleName, CPU,
                                                                  FeaturesStr);
    assert(STI && "Unable to create subtarget info!");

    MCDisassembler *DisAsm = TheTarget->createMCDisassembler(*STI);
    assert(DisAsm && "Unable to create disassembler!");

    int AsmPrinterVariant = MAI->getAssemblerDialect();
    MCInstPrinter *IP = TheTarget->createMCInstPrinter(AsmPrinterVariant,
                                                     *MAI, *MII, *MRI, *STI);
    assert(IP && "Unable to create instruction printer!");

    SimpleMemoryObject SMO;
    SMO.Bytes = (uint8_t*)data;
    SMO.Size = numBytes;
    uint64_t Size;
    fflush(stdout);
    raw_fd_ostream Out(fileno(stdout), false);
    for(int i = 0, b = 0; b < numBytes || i < numInst; i++, b += Size) {
        MCInst Inst;
        MCDisassembler::DecodeStatus S = DisAsm->getInstruction(Inst, Size, SMO, 0, nulls(), Out);
        if(MCDisassembler::Fail == S || MCDisassembler::SoftFail == S)
            break;
        Out << (void*) ((uintptr_t)data + b) << "(+" << b << ")" << ":\t";
        IP->printInst(&Inst,Out,"");
        Out << "\n";
        SMO.Size -= Size; SMO.Bytes += Size;
    }
    Out.flush();
    delete MAI; delete MRI; delete STI; delete MII; delete DisAsm; delete IP;
}

//adapted from LLVM's C interface "LLVMTargetMachineEmitToFile"
bool llvmutil_emitobjfile(Module * Mod, TargetMachine * TM, raw_ostream & dest, std::string * ErrorMessage) {

    PassManager pass;

    llvmutil_addtargetspecificpasses(&pass, TM);
    
    TargetMachine::CodeGenFileType ft = TargetMachine::CGFT_ObjectFile;
    
    formatted_raw_ostream destf(dest);
    
    if (TM->addPassesToEmitFile(pass, destf, ft)) {
        *ErrorMessage = "addPassesToEmitFile";
        return true;
    }

    pass.run(*Mod);
    destf.flush();
    dest.flush();

    return false;
}

static char * copyName(const StringRef & name) {
    return strdup(name.str().c_str());
}

#if defined(LLVM_3_3) ||  defined(LLVM_3_4)

struct CopyConnectedComponent : public ValueMaterializer {
    Module * dest;
    Module * src;
    llvmutil_Property copyGlobal;
    void * data;
    ValueToValueMapTy & VMap;
    CopyConnectedComponent(Module * dest_, Module * src_, llvmutil_Property copyGlobal_, void * data_, ValueToValueMapTy & VMap_)
    : dest(dest_), src(src_), copyGlobal(copyGlobal_), data(data_), VMap(VMap_) {
    }
    virtual Value * materializeValueFor(Value * V) {
        if(Function * fn = dyn_cast<Function>(V)) {
            assert(fn->getParent() == src);
            Function * newfn = dest->getFunction(fn->getName());
            if(!newfn) {
                newfn = Function::Create(fn->getFunctionType(),fn->getLinkage(), fn->getName(),dest);
                newfn->copyAttributesFrom(fn);
            }
            if(!fn->isDeclaration() && newfn->isDeclaration() && copyGlobal(fn,data)) {
                for(Function::arg_iterator II = newfn->arg_begin(), I = fn->arg_begin(), E = fn->arg_end(); I != E; ++I, ++II) {
                    II->setName(I->getName());
                    VMap[I] = II;
                }
                VMap[fn] = newfn;
                SmallVector<ReturnInst*,8> Returns;
                CloneFunctionInto(newfn, fn, VMap, true, Returns, "", NULL, NULL, this);
            }
            return newfn;
        } else if(GlobalVariable * GV = dyn_cast<GlobalVariable>(V)) {
            GlobalVariable * newGV = dest->getGlobalVariable(GV->getName(),true);
            if(!newGV) {
                newGV = new GlobalVariable(*dest,GV->getType()->getElementType(),GV->isConstant(),GV->getLinkage(),NULL,GV->getName(),NULL,GlobalVariable::NotThreadLocal,GV->getType()->getAddressSpace());
                newGV->copyAttributesFrom(GV);
                if(!GV->isDeclaration()) {
                    if(!copyGlobal(GV,data)) {
                        newGV->setExternallyInitialized(true);
                    } else if(GV->hasInitializer()) {
                        Value * C = MapValue(GV->getInitializer(),VMap,RF_None,NULL,this);
                        newGV->setInitializer(cast<Constant>(C));
                    }
                }
            }
            return newGV;
        }
        return NULL;
    }
};

llvm::Module * llvmutil_extractmodulewithproperties(llvm::StringRef DestName, llvm::Module * Src, llvm::GlobalValue ** gvs, size_t N, llvmutil_Property copyGlobal, void * data, llvm::ValueToValueMapTy & VMap) {
    Module * Dest = new Module(DestName,Src->getContext());
    CopyConnectedComponent cp(Dest,Src,copyGlobal,data,VMap);
    for(size_t i = 0; i < N; i++)
        cp.materializeValueFor(gvs[i]);
    return Dest;
}
static bool AlwaysCopy(GlobalValue * G, void *) { return true; }
#endif



Module * llvmutil_extractmodule(Module * OrigMod, TargetMachine * TM, std::vector<llvm::GlobalValue*> * livevalues, std::vector<std::string> * symbolnames, bool internalize) {
        assert(symbolnames == NULL || livevalues->size() == symbolnames->size());
        ValueToValueMapTy VMap;
        #if defined(LLVM_3_3) || defined(LLVM_3_4)
        Module * M = llvmutil_extractmodulewithproperties(OrigMod->getModuleIdentifier(), OrigMod, (llvm::GlobalValue **)&(*livevalues)[0], livevalues->size(), AlwaysCopy, NULL, VMap);
        #else
        Module * M = CloneModule(OrigMod, VMap);
        internalize = true; //we need to do this regardless of the input because it is the only way we can extract just the needed functions from the module
        #endif
        PassManager * MPM = new PassManager();
        
        llvmutil_addtargetspecificpasses(MPM, TM);
        
        std::vector<const char *> names;
        for(size_t i = 0; i < livevalues->size(); i++) {
            GlobalValue * fn = cast<GlobalValue>(VMap[(*livevalues)[i]]);
            if(symbolnames) {
                std::string name = (*symbolnames)[i];
                GlobalValue * gv = M->getNamedValue(name);
                if(gv) { //if there is already a symbol with this name, rename it
                    gv->setName(Twine((*symbolnames)[i],"_renamed"));
                }
                fn->setName(name); //and set our function to this name
                assert(fn->getName() == name);
            }
            names.push_back(copyName(fn->getName())); //internalize pass has weird interface, so we need to copy the names here
        }
        
        //at this point we run optimizations on the module
        //first internalize all functions not mentioned in "names" using an internalize pass and then perform 
        //standard optimizations
        
        MPM->add(createVerifierPass()); //make sure we haven't messed stuff up yet
        if (internalize)
            MPM->add(createInternalizePass(names));
        MPM->add(createGlobalDCEPass()); //run this early since anything not in the table of exported functions is still in this module
                                         //this will remove dead functions
        
        PassManagerBuilder PMB;
        PMB.OptLevel = 3;
        PMB.DisableUnrollLoops = true;
        
        PMB.populateModulePassManager(*MPM);
        //PMB.populateLTOPassManager(*MPM, false, false); //no need to re-internalize, we already did it
    
        MPM->run(*M);
        
        delete MPM;
        MPM = NULL;
    
        for(size_t i = 0; i < names.size(); i++) {
            free((char*)names[i]);
            names[i] = NULL;
        }
        return M;
}

bool llvmutil_linkmodule(Module * dst, Module * src, TargetMachine * TM, PassManager ** optManager, std::string * errmsg) {
    //cleanup after clang.
    //in some cases clang will mark stuff AvailableExternally (e.g. atoi on linux)
    //the linker will then delete it because it is not used.
    //switching it to WeakODR means that the linker will keep it even if it is not used
    for(llvm::Module::iterator it = src->begin(), end = src->end();
        it != end;
        ++it) {
        llvm::Function * fn = it;
        if(fn->hasAvailableExternallyLinkage()) {
            fn->setLinkage(llvm::GlobalValue::WeakODRLinkage);
        }
        if(fn->hasDLLImportLinkage()) { //clear dll import linkage because it messes up the jit on window
            fn->setLinkage(llvm::GlobalValue::ExternalLinkage);
        }
    }
    
    if(optManager) {
        if(!*optManager) {
            *optManager = new PassManager();
            llvmutil_addtargetspecificpasses(*optManager, TM);
            (*optManager)->add(createFunctionInliningPass());
            OptInfo oi;
            llvmutil_addoptimizationpasses(*optManager, &oi);
        }
        (*optManager)->run(*src);
    }
    
    return llvm::Linker::LinkModules(dst, src, 0, errmsg);
}

