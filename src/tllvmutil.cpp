#include "tllvmutil.h"
#include "llvm/Target/TargetLibraryInfo.h"
#include "llvm-c/Disassembler.h"
using namespace llvm;

void llvmutil_addtargetspecificpasses(PassManagerBase * fpm, TargetMachine * TM) {
    fpm->add(new TargetLibraryInfo(Triple(TM->getTargetTriple())));
    fpm->add(new TARGETDATA()(*TM->TARGETDATA(get)()));
#ifdef LLVM_3_2
    fpm->add(new TargetTransformInfo(TM->getScalarTargetTransformInfo(),
                                     TM->getVectorTargetTransformInfo()));
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

void llvmutil_disassemblefunction(void * data, size_t sz) {
#ifndef __linux__
    printf("assembly for function at address %p\n",data);
    LLVMDisasmContextRef disasm = LLVMCreateDisasm(llvm::sys::getDefaultTargetTriple().c_str(),NULL,0,NULL,NULL);
    assert(disasm != NULL);
    char buf[1024];
    buf[0] = '\0';
    int64_t offset = 0;
    while(offset < sz) {
        int64_t inc = LLVMDisasmInstruction(disasm, (uint8_t*)data + offset, sz - offset, 0, buf,1024);
        printf("%d:\t%s\n",(int)offset,buf);
        offset += inc;
    }
    LLVMDisasmDispose(disasm);
#endif
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