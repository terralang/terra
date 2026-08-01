#include "llvmheaders.h"
#include "tinline.h"

#if LLVM_VERSION < 170

using namespace llvm;

ManualInliner::ManualInliner(TargetMachine *TM, Module *m) {
    // Trick the Module-at-a-time inliner into running on a single SCC
    // First we run it on the (currently empty) module to initialize
    // the inlining pass with the Analysis passes it needs.

    PM.add(createTargetTransformInfoWrapperPass(TM->getTargetIRAnalysis()));

    SI = (CallGraphSCCPass *)createFunctionInliningPass();
    PM.add(SI);
    PM.run(*m);
    // save the call graph so we can keep it up to date
    CallGraphWrapperPass &CGW = SI->getAnalysis<CallGraphWrapperPass>();
    CGW.runOnModule(*m);  // force it to realloc the CG
    CG = &CGW.getCallGraph();
    assert(CG);
}
// Inliner handles erasing functions since it also maintains a copy of the callgraph
// that needs to be kept up to date with the functions in the module
void ManualInliner::eraseFunction(Function *F) {
    CallGraphNode *n = CG->getOrInsertFunction(F);
    n->removeAllCalledFunctions();
    CG->removeFunctionFromModule(n);
    delete F;
}
void ManualInliner::run(std::vector<Function *>::iterator fbegin,
                        std::vector<Function *>::iterator fend) {
    std::vector<CallGraphNode *> nodes;
    // the inliner requires an up to date callgraph, so we add the functions in the SCC
    // to the callgraph. If needed, we can do this during function creation to make it
    // faster
    for (std::vector<Function *>::iterator fp = fbegin; fp != fend; ++fp) {
        Function *F = *fp;
        CallGraphNode *n = CG->getOrInsertFunction(F);
        for (Function::iterator BB = F->begin(), BBE = F->end(); BB != BBE; ++BB)
            for (BasicBlock::iterator II = BB->begin(), IE = BB->end(); II != IE; ++II) {
                CallBase *CS(dyn_cast<CallBase>(II));
                if (CS) {
                    const Function *Callee = CS->getCalledFunction();
                    if (Callee && !Callee->isIntrinsic()) {
                        CallGraphNode *n2 = CG->getOrInsertFunction(Callee);
                        n->addCalledFunction(CS, n2);
                    }
                }
            }
        nodes.push_back(n);
    }
    // create a fake SCC node and manually run the inliner pass on it.
    CallGraphSCC SCC(*CG, NULL);

    SCC.initialize(ArrayRef<CallGraphNode *>(nodes));
    SI->runOnSCC(SCC);
    // We optimize the function now, which will invalidate the call graph,
    // removing called functions makes sure that further inlining passes don't attempt to
    // add invalid callsites as inlining candidates
    for (std::vector<Function *>::iterator fp = fbegin; fp != fend; ++fp) {
        CG->getOrInsertFunction(*fp)->removeAllCalledFunctions();
    }
}

#else  // LLVM_VERSION >= 170

// LLVM 17 removed the legacy pass manager pipeline Terra used to borrow the
// inliner from: the new inliner is a CGSCC pass that can only be driven through
// LazyCallGraph and CGSCCUpdateResult, neither of which can be kept up to date
// while Terra adds functions to the module one at a time. So instead we drive
// the pieces the inliner is built out of -- getInlineCost, shouldInline and
// InlineFunction -- directly. This mirrors InlinerPass::run and
// DefaultInlineAdvisor::getAdviceImpl, minus the call graph bookkeeping.

#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/Analysis/AssumptionCache.h"
#include "llvm/Analysis/BlockFrequencyInfo.h"
#include "llvm/Analysis/InlineAdvisor.h"
#include "llvm/Analysis/InlineCost.h"
#include "llvm/Analysis/OptimizationRemarkEmitter.h"
#include "llvm/Analysis/ProfileSummaryInfo.h"
#include "llvm/Analysis/TargetLibraryInfo.h"
#include "llvm/Analysis/TargetTransformInfo.h"
#include "llvm/IR/ValueHandle.h"
#include "llvm/Transforms/Utils/Cloning.h"

using namespace llvm;

// Terra's function pipeline is built at -O3, so match the inlining thresholds
// LLVM would use for a -O3 module pipeline.
ManualInliner::ManualInliner(TargetMachine *TM, Module *m, FunctionAnalysisManager &fam,
                             ModuleAnalysisManager &mam)
        : M(m), FAM(&fam), MAM(&mam), Params(getInlineParams(3, 0)) {}

// Return true if the given inline history includes F. A call site inherits the
// history of the call that exposed it, so this is what stops us from inlining a
// recursive cycle forever.
static bool inlineHistoryIncludes(
        Function *F, int HistoryID,
        const SmallVectorImpl<std::pair<Function *, int> > &InlineHistory) {
    while (HistoryID != -1) {
        assert(unsigned(HistoryID) < InlineHistory.size() && "invalid inline history ID");
        if (InlineHistory[HistoryID].first == F) return true;
        HistoryID = InlineHistory[HistoryID].second;
    }
    return false;
}

static bool isInlineCandidate(CallBase *CB) {
    if (isa<IntrinsicInst>(CB)) return false;
    // Indirect calls have nothing to inline. LLVM's inliner additionally tries
    // tryPromoteCall to devirtualize them first; we don't bother.
    Function *Callee = CB->getCalledFunction();
    return Callee && !Callee->isDeclaration();
}

void ManualInliner::run(std::vector<Function *>::iterator fbegin,
                        std::vector<Function *>::iterator fend) {
    SmallPtrSet<Function *, 8> SCCFunctions(fbegin, fend);

    ProfileSummaryInfo *PSI = &MAM->getResult<ProfileSummaryAnalysis>(*M);
    auto GetAssumptionCache = [&](Function &F) -> AssumptionCache & {
        return FAM->getResult<AssumptionAnalysis>(F);
    };
    auto GetBFI = [&](Function &F) -> BlockFrequencyInfo & {
        return FAM->getResult<BlockFrequencyAnalysis>(F);
    };
    auto GetTLI = [&](Function &F) -> const TargetLibraryInfo & {
        return FAM->getResult<TargetLibraryAnalysis>(F);
    };
    auto GetInlineCost = [&](CallBase &CB) -> InlineCost {
        Function &Callee = *CB.getCalledFunction();
        TargetTransformInfo &CalleeTTI = FAM->getResult<TargetIRAnalysis>(Callee);
        return getInlineCost(CB, Params, CalleeTTI, GetAssumptionCache, GetTLI, GetBFI,
                             PSI);
    };

    // Collect the call sites in this SCC up front. Sites exposed by inlining are
    // appended as we go, tagged with the history of what was inlined to create
    // them. Weak handles because inlining can delete instructions in the caller.
    SmallVector<std::pair<WeakTrackingVH, int>, 16> Calls;
    SmallVector<std::pair<Function *, int>, 8> InlineHistory;
    for (std::vector<Function *>::iterator fp = fbegin; fp != fend; ++fp)
        for (BasicBlock &BB : **fp)
            for (Instruction &I : BB)
                if (CallBase *CB = dyn_cast<CallBase>(&I))
                    if (isInlineCandidate(CB)) Calls.push_back({CB, -1});
    if (Calls.empty()) return;

    // Inline calls that leave the SCC before calls that stay inside it, so that
    // a recursive function is fully built out before we consider unrolling it
    // into itself. This is what LLVM's inliner does with its SCC worklist.
    std::stable_partition(
            Calls.begin(), Calls.end(), [&](const std::pair<WeakTrackingVH, int> &C) {
                return !SCCFunctions.count(cast<CallBase>(C.first)->getCalledFunction());
            });

    InlineFunctionInfo IFI(GetAssumptionCache, PSI);
    SmallPtrSet<Function *, 8> Inlined;

    for (unsigned i = 0; i < Calls.size(); ++i) {
        CallBase *CB = dyn_cast_or_null<CallBase>(Calls[i].first);
        if (!CB || !isInlineCandidate(CB)) continue;
        int HistoryID = Calls[i].second;
        Function *Callee = CB->getCalledFunction();
        Function *Caller = CB->getCaller();

        // Don't chase a cycle we have already been around once.
        if (HistoryID != -1 && inlineHistoryIncludes(Callee, HistoryID, InlineHistory))
            continue;

        OptimizationRemarkEmitter &ORE =
                FAM->getResult<OptimizationRemarkEmitterAnalysis>(*Caller);
        // shouldInline layers the "would it be better to inline the caller into
        // its own callers instead" deferral heuristic over the raw cost, and
        // returns nullopt when we should leave the call alone.
        if (!shouldInline(*CB,
#if LLVM_VERSION >= 200
                          FAM->getResult<TargetIRAnalysis>(*Callee),
#endif
                          GetInlineCost, ORE))
            continue;

        IFI.reset();
        if (!InlineFunction(*CB, IFI, /*MergeAttributes=*/true).isSuccess()) continue;
        Inlined.insert(Caller);

        // Anything the callee used to call is now a call site in the caller.
        if (!IFI.InlinedCallSites.empty()) {
            int NewHistoryID = InlineHistory.size();
            InlineHistory.push_back({Callee, HistoryID});
            for (CallBase *NewCB : IFI.InlinedCallSites)
                if (isInlineCandidate(NewCB)) Calls.push_back({NewCB, NewHistoryID});
        }
    }

    // Cached analyses for anything we changed are stale; the function pipeline
    // runs on these functions next.
    for (Function *F : Inlined) FAM->invalidate(*F, PreservedAnalyses::none());
}

#endif
