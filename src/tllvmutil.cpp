/* See Copyright Notice in ../LICENSE.txt */

#include <stdio.h>

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