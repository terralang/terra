#ifdef TERRA_LLVM_HEADERS_HAVE_NDEBUG
//somewhere in LLVM's header files they define an object differently
//if NDEBUG is on, causing CallGraph functions to crash.
//we compile this file with a matching NDEBUG setting to get around this
#define NDEBUG
#endif
#include "llvmheaders.h"
#include "tinline.h"

using namespace llvm;

ManualInliner::ManualInliner(TargetMachine * TM, Module * m) {
    //Trick the Module-at-a-time inliner into running on a single SCC
    //First we run it on the (currently empty) module to initialize
    //the inlining pass with the Analysis passes it needs.
    #if LLVM_VERSION <= 35
    DataLayout * TD = new DataLayout(*TM->getDataLayout());
    #endif
    
    #if LLVM_VERSION <= 34
    PM.add(TD);
    #elif LLVM_VERSION <= 35
    PM.add(new DataLayoutPass(*TD));
    #elif LLVM_VERSION <= 36
    PM.add(new DataLayoutPass());
    #else
    PM.add(createTargetTransformInfoWrapperPass(TM->getTargetIRAnalysis()));
    #endif
    
    #if LLVM_VERSION >= 33 && LLVM_VERSION <= 36
    TM->addAnalysisPasses(PM);
    #endif
    SI = (CallGraphSCCPass*) createFunctionInliningPass();
    PM.add(SI);
    PM.run(*m);
    //save the call graph so we can keep it up to date
    #if LLVM_VERSION <= 34
    CG = &SI->getAnalysis<CallGraph>();
    #else
    CallGraphWrapperPass & CGW = SI->getAnalysis<CallGraphWrapperPass>();
    CGW.runOnModule(*m); //force it to realloc the CG
    CG = &CGW.getCallGraph();
    assert(CG);
    #endif
}
//Inliner handles erasing functions since it also maintains a copy of the callgraph
//that needs to be kept up to date with the functions in the module
void ManualInliner::eraseFunction(Function * F) {
    CallGraphNode * n = CG->getOrInsertFunction(F);
    n->removeAllCalledFunctions();
    CG->removeFunctionFromModule(n);
    delete F;
}
void ManualInliner::run(std::vector<Function *>::iterator fbegin, std::vector<Function *>::iterator fend) {
    std::vector<CallGraphNode*> nodes;
    //the inliner requires an up to date callgraph, so we add the functions in the SCC
    //to the callgraph. If needed, we can do this during function creation to make it faster
    for(std::vector<Function *>::iterator fp = fbegin; fp != fend; ++fp){
        Function * F = *fp;
        CallGraphNode * n = CG->getOrInsertFunction(F);
        for (Function::iterator BB = F->begin(), BBE = F->end(); BB != BBE; ++BB)
          for (BasicBlock::iterator II = BB->begin(), IE = BB->end(); II != IE; ++II) {
            CallSite CS(cast<Value>(II));
            if (CS) {
              const Function *Callee = CS.getCalledFunction();
              if (Callee && !Callee->isIntrinsic()) {
                CallGraphNode * n2 = CG->getOrInsertFunction(Callee);
                n->addCalledFunction(CS,n2);
              }
            }
        }
        nodes.push_back(n);
    }
    //create a fake SCC node and manually run the inliner pass on it.
#if LLVM_VERSION < 39
    CallGraphSCC SCC(NULL);
#else
    CallGraphSCC SCC(*CG,NULL);
#endif

#if LLVM_VERSION >= 50
    SCC.initialize(ArrayRef<CallGraphNode *>(nodes));
#else
    SCC.initialize(&nodes[0], &nodes[0]+nodes.size());
#endif
    SI->runOnSCC(SCC);
    //We optimize the function now, which will invalidate the call graph,
    //removing called functions makes sure that further inlining passes don't attempt to add invalid callsites as inlining candidates
    for(std::vector<Function *>::iterator fp = fbegin; fp != fend; ++fp){
        CG->getOrInsertFunction(*fp)->removeAllCalledFunctions();
    }

}
