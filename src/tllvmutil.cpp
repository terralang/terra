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
#if LLVM_VERSION >= 35
#include "llvm/MC/MCContext.h"
#endif
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
    TARGETDATA() * TD = new TARGETDATA()(*TM->TARGETDATA(get)());
#if LLVM_VERSION <= 34
    fpm->add(TD);
#else
    fpm->add(new DataLayoutPass(*TD));
#endif
    
#if LLVM_VERSION == 32
    fpm->add(new TargetTransformInfo(TM->getScalarTargetTransformInfo(),
                                     TM->getVectorTargetTransformInfo()));
#elif LLVM_VERSION >= 33
    TM->addAnalysisPasses(*fpm);
#endif
}

class PassManagerWrapper : public PassManagerBase {
public:
    PassManagerBase * PM;
    PassManagerWrapper(PassManagerBase * PM_) : PM(PM_) {}
    virtual void add(Pass *P) {
        if(P->getPotentialPassManagerType() > PMT_CallGraphPassManager || P->getAsImmutablePass() != NULL)
            PM->add(P);
    }
};
void llvmutil_addoptimizationpasses(PassManagerBase * fpm) {
    PassManagerBuilder PMB;
    PMB.OptLevel = 3;
    PMB.SizeLevel = 0;
    PMB.DisableUnitAtATime = true;
#if LLVM_VERSION <= 34 && LLVM_VERSION >= 32
    PMB.LoopVectorize = false;
#elif LLVM_VERSION >= 35
    PMB.LoopVectorize = true;
    PMB.SLPVectorize = true;
#endif

    PassManagerWrapper W(fpm);
    PMB.populateModulePassManager(W);
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
#if LLVM_VERSION >= 34
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

#if LLVM_VERSION >= 35
    MCContext Ctx(MAI,MRI, NULL);
    MCDisassembler *DisAsm = TheTarget->createMCDisassembler(*STI,Ctx);
#else
    MCDisassembler *DisAsm = TheTarget->createMCDisassembler(*STI);
#endif
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
    for(size_t i = 0, b = 0; b < numBytes || i < numInst; i++, b += Size) {
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

#if LLVM_VERSION >= 34

struct CopyConnectedComponent : public ValueMaterializer {
    Module * dest;
    Module * src;
    llvmutil_Property copyGlobal;
    void * data;
    ValueToValueMapTy & VMap;
    DIBuilder * DI;
    DICompileUnit NCU;
    CopyConnectedComponent(Module * dest_, Module * src_, llvmutil_Property copyGlobal_, void * data_, ValueToValueMapTy & VMap_)
    : dest(dest_), src(src_), copyGlobal(copyGlobal_), data(data_), VMap(VMap_), DI(NULL) {
        if(NamedMDNode * NMD = src->getNamedMetadata("llvm.module.flags")) {
            NamedMDNode * New = dest->getOrInsertNamedMetadata(NMD->getName());
            for (unsigned i = 0; i < NMD->getNumOperands(); i++) {
                New->addOperand(MapValue(NMD->getOperand(i), VMap));
            }
        }

        if(NamedMDNode * CUN = src->getNamedMetadata("llvm.dbg.cu")) {
            DI = new DIBuilder(*dest);
            DICompileUnit CU(CUN->getOperand(0));
            NCU = DI->createCompileUnit(CU.getLanguage(), CU.getFilename(), CU.getDirectory(), CU.getProducer(), CU.isOptimized(), CU.getFlags(), CU.getRunTimeVersion());
        }
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
        } else if(MDNode * MD = dyn_cast<MDNode>(V)) {
            DISubprogram SP(MD);
            if(DI != NULL && SP.isSubprogram()) {
                
                if(Function * OF = SP.getFunction()) {
                    Function * F = cast<Function>(MapValue(OF,VMap,RF_None,NULL,this));
                    DISubprogram NSP = DI->createFunction(SP.getContext(), SP.getName(), SP.getLinkageName(),
                                                      DI->createFile(SP.getFilename(),SP.getDirectory()),
                                                      SP.getLineNumber(), SP.getType(),
                                                      SP.isLocalToUnit(), SP.isDefinition(),
                                                      SP.getScopeLineNumber(),SP.getFlags(),SP.isOptimized(),
                                                      F);
                    return NSP;
                }
                /* fallthrough */
            }
            /* fallthrough */
        }
        return NULL;
    }
    void finalize() {
        if(DI) {
            DI->finalize();
            delete DI;
        }
    }
};

llvm::Module * llvmutil_extractmodulewithproperties(llvm::StringRef DestName, llvm::Module * Src, llvm::GlobalValue ** gvs, size_t N, llvmutil_Property copyGlobal, void * data, llvm::ValueToValueMapTy & VMap) {
    Module * Dest = new Module(DestName,Src->getContext());
    Dest->setTargetTriple(Src->getTargetTriple());
    CopyConnectedComponent cp(Dest,Src,copyGlobal,data,VMap);
    for(size_t i = 0; i < N; i++)
        cp.materializeValueFor(gvs[i]);
    cp.finalize();
    return Dest;
}
static bool AlwaysCopy(GlobalValue * G, void *) { return true; }
#endif



Module * llvmutil_extractmodule(Module * OrigMod, TargetMachine * TM, std::vector<llvm::GlobalValue*> * livevalues, std::vector<std::string> * symbolnames, bool internalize) {
        assert(symbolnames == NULL || livevalues->size() == symbolnames->size());
        ValueToValueMapTy VMap;
        #if LLVM_VERSION >= 34
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
        PMB.SizeLevel = 0;
    
#if LLVM_VERSION >= 35
        PMB.LoopVectorize = true;
        PMB.SLPVectorize = true;
#endif

        PMB.populateModulePassManager(*MPM);
    
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
    #if LLVM_VERSION >= 35
        if(fn->hasDLLImportStorageClass()) //clear dll import linkage because it messes up the jit on window
            fn->setDLLStorageClass(llvm::GlobalValue::DefaultStorageClass);
    #else
        if(fn->hasDLLImportLinkage()) //clear dll import linkage because it messes up the jit on window
            fn->setLinkage(llvm::GlobalValue::ExternalLinkage);
        
    #endif
    }
    src->setTargetTriple(dst->getTargetTriple()); //suppress warning that occur due to unmatched os versions
    if(optManager) {
        if(!*optManager) {
            *optManager = new PassManager();
            llvmutil_addtargetspecificpasses(*optManager, TM);
            (*optManager)->add(createFunctionInliningPass());
            llvmutil_addoptimizationpasses(*optManager);
        }
        (*optManager)->run(*src);
    }
    
    return llvm::Linker::LinkModules(dst, src, 0, errmsg);
}

