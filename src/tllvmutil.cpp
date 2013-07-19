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
    fpm->add(new TargetLibraryInfo(Triple(TM->getTargetTriple())));
    fpm->add(new TARGETDATA()(*TM->TARGETDATA(get)()));
#ifdef LLVM_3_2
    fpm->add(new TargetTransformInfo(TM->getScalarTargetTransformInfo(),
                                     TM->getVectorTargetTransformInfo()));
#elif LLVM_3_3
    TM->addAnalysisPasses(*fpm);
#endif
}


void llvmutil_addoptimizationpasses(FunctionPassManager * fpm, const OptInfo * oi) {
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
    if (!oi->DisableSimplifyLibCalls)
        fpm->add(createSimplifyLibCallsPass());    // Library Call Optimizations
    
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

void llvmutil_disassemblefunction(void * data, size_t numBytes) {
    InitializeNativeTargetDisassembler();
    std::string Error;
    std::string TripleName = llvm::sys::getDefaultTargetTriple();
    const Target *TheTarget = TargetRegistry::lookupTarget(TripleName, Error);
    assert(TheTarget && "Unable to create target!");
    const MCAsmInfo *MAI = TheTarget->createMCAsmInfo(TripleName);
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

    printf("assembly for function at address %p\n",data);
    SimpleMemoryObject SMO;
    SMO.Bytes = (uint8_t*)data;
    SMO.Size = numBytes;
    uint64_t Size;
    fflush(stdout);
    raw_fd_ostream Out(STDOUT_FILENO, false);
    for(int i = 0; i < numBytes; i += Size) {
        MCInst Inst;
        MCDisassembler::DecodeStatus S = DisAsm->getInstruction(Inst, Size, SMO, 0, nulls(), Out);
        if(MCDisassembler::Fail == S || MCDisassembler::SoftFail == S)
            break;
        Out << i << ":\t";
        IP->printInst(&Inst,Out,"");
        Out << "\n";
        SMO.Size -= Size; SMO.Bytes += Size;
    }
    Out.flush();
    delete MAI; delete MRI; delete STI; delete MII; delete DisAsm; delete IP;
}

//adapted from LLVM's C interface "LLVMTargetMachineEmitToFile"
bool llvmutil_emitobjfile(Module * Mod, TargetMachine * TM, const char * Filename, std::string * ErrorMessage) {

    PassManager pass;

    llvmutil_addtargetspecificpasses(&pass, TM);
    
    TargetMachine::CodeGenFileType ft = TargetMachine::CGFT_ObjectFile;
    
    raw_fd_ostream dest(Filename, *ErrorMessage, raw_fd_ostream::F_Binary);
    formatted_raw_ostream destf(dest);
    if (!ErrorMessage->empty()) {
        return true;
    }

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

Module * llvmutil_extractmodule(Module * OrigMod, TargetMachine * TM, std::vector<Function*> * livefns, std::vector<std::string> * symbolnames) {
        assert(symbolnames == NULL || livefns->size() == symbolnames->size());
        ValueToValueMapTy VMap;
        Module * M = CloneModule(OrigMod, VMap);
        PassManager * MPM = new PassManager();
        
        llvmutil_addtargetspecificpasses(MPM, TM);
        
        std::vector<const char *> names;
        for(size_t i = 0; i < livefns->size(); i++) {
            Function * fn = cast<Function>(VMap[(*livefns)[i]]);
            const char * name;
            if(symbolnames) {
                GlobalAlias * ga = new GlobalAlias(fn->getType(), Function::ExternalLinkage, (*symbolnames)[i], fn, M);
                name = copyName(ga->getName());
            } else {
                name = copyName(fn->getName());
            }
            names.push_back(name); //internalize pass has weird interface, so we need to copy the names here
        }
        
        //at this point we run optimizations on the module
        //first internalize all functions not mentioned in "names" using an internalize pass and then perform 
        //standard optimizations
        
        MPM->add(createVerifierPass()); //make sure we haven't messed stuff up yet
        MPM->add(createInternalizePass(names));
        MPM->add(createGlobalDCEPass()); //run this early since anything not in the table of exported functions is still in this module
                                         //this will remove dead functions
        
        //clean up the name list
        for(size_t i = 0; i < names.size(); i++) {
            free((char*)names[i]);
            names[i] = NULL;
        }
        
        PassManagerBuilder PMB;
        PMB.OptLevel = 3;
        PMB.DisableUnrollLoops = true;
        
        PMB.populateModulePassManager(*MPM);
        //PMB.populateLTOPassManager(*MPM, false, false); //no need to re-internalize, we already did it
    
        MPM->run(*M);
        
        delete MPM;
        MPM = NULL;
    
        return M;
}
