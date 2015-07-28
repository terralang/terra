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

#ifndef _WIN32
#include <sys/wait.h>
#endif

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
    DataLayout * TD = new DataLayout(*GetDataLayout(TM));
#if LLVM_VERSION <= 34
    fpm->add(TD);
#elif LLVM_VERSION == 35
    fpm->add(new DataLayoutPass(*TD));
#else
    (void) TD;
    fpm->add(new DataLayoutPass());
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
  uint64_t getBase() const { return 0; }
  uint64_t getExtent() const { return ~0ULL; }
  int readByte(uint64_t Addr, uint8_t *Byte) const {
    *Byte = *(uint8_t*)Addr;
    return 0;
  }
};

void llvmutil_disassemblefunction(void * data, size_t numBytes, size_t numInst) {
    InitializeNativeTargetDisassembler();
    std::string Error;
#if LLVM_VERSION >= 33
    std::string TripleName = llvm::sys::getProcessTriple();
#else
    std::string TripleName = llvm::sys::getDefaultTargetTriple();
#endif    
    std::string CPU = llvm::sys::getHostCPUName();

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

    #if LLVM_VERSION < 36
    SimpleMemoryObject SMO;
    #else
    ArrayRef<uint8_t> Bytes((uint8_t*)data,numBytes);
    #endif
    
    uint64_t addr = (uint64_t)data;
    uint64_t Size;
    fflush(stdout);
    raw_fd_ostream Out(fileno(stdout), false);
    for(size_t i = 0, b = 0; b < numBytes || i < numInst; i++, b += Size) {
        MCInst Inst;
        #if LLVM_VERSION >= 36
        MCDisassembler::DecodeStatus S = DisAsm->getInstruction(Inst, Size, Bytes.slice(b),addr + b, nulls(), Out);
        #else
        MCDisassembler::DecodeStatus S = DisAsm->getInstruction(Inst, Size, SMO,addr + b, nulls(), Out);
        #endif
        if(MCDisassembler::Fail == S || MCDisassembler::SoftFail == S)
            break;
        Out << (void*) ((uintptr_t)data + b) << "(+" << b << ")" << ":\t";
        IP->printInst(&Inst,Out,"");
        Out << "\n";
    }
    Out.flush();
    delete MAI; delete MRI; delete STI; delete MII; delete DisAsm; delete IP;
}

//adapted from LLVM's C interface "LLVMTargetMachineEmitToFile"
bool llvmutil_emitobjfile(Module * Mod, TargetMachine * TM, bool outputobjectfile, raw_ostream & dest) {

    PassManager pass;

    llvmutil_addtargetspecificpasses(&pass, TM);
    
    TargetMachine::CodeGenFileType ft = outputobjectfile? TargetMachine::CGFT_ObjectFile : TargetMachine::CGFT_AssemblyFile;
    
    formatted_raw_ostream destf(dest);
    
    if (TM->addPassesToEmitFile(pass, destf, ft)) {
        return true;
    }

    pass.run(*Mod);
    destf.flush();
    dest.flush();

    return false;
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
    : dest(dest_), src(src_), copyGlobal(copyGlobal_), data(data_), VMap(VMap_), DI(NULL) {}
    
    void CopyDebugMetadata() {
        if(NamedMDNode * NMD = src->getNamedMetadata("llvm.module.flags")) {
            NamedMDNode * New = dest->getOrInsertNamedMetadata(NMD->getName());
            for (unsigned i = 0; i < NMD->getNumOperands(); i++) {
            #if LLVM_VERSION <= 35
                New->addOperand(MapValue(NMD->getOperand(i), VMap));
            #else
                New->addOperand(MapMetadata(NMD->getOperand(i), VMap));
            #endif
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
#if LLVM_VERSION <= 35
        } else if(MDNode * MD = dyn_cast<MDNode>(V)) {
            DISubprogram SP(MD);
            if(DI != NULL && SP.isSubprogram()) {
#else
        } else if(auto * MDV = dyn_cast<MetadataAsValue>(V)) {
            Metadata * MDraw = MDV->getMetadata();
            MDNode * MD = dyn_cast<MDNode>(MDraw);
            DISubprogram SP(MD);
            if(MD != NULL && DI != NULL && SP.isSubprogram()) {
#endif
           
                
                if(Function * OF = SP.getFunction()) {
                    Function * F = cast<Function>(MapValue(OF,VMap,RF_None,NULL,this));
                    DISubprogram NSP = DI->createFunction(SP.getContext(), SP.getName(), SP.getLinkageName(),
                                                      DI->createFile(SP.getFilename(),SP.getDirectory()),
                                                      SP.getLineNumber(), SP.getType(),
                                                      SP.isLocalToUnit(), SP.isDefinition(),
                                                      SP.getScopeLineNumber(),SP.getFlags(),SP.isOptimized(),
                                                      F);
                    #if LLVM_VERSION <= 35
                    return NSP;
                    #else
                    return MetadataAsValue::get(dest->getContext(),NSP);
                    #endif
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
    cp.CopyDebugMetadata();
    for(size_t i = 0; i < N; i++)
        MapValue(gvs[i],VMap,RF_None,NULL,&cp);
    cp.finalize();
    return Dest;
}
void llvmutil_copyfrommodule(llvm::Module * Dest, llvm::Module * Src, llvm::GlobalValue ** gvs, size_t N, llvmutil_Property copyGlobal, void * data) {
    llvm::ValueToValueMapTy VMap;
    CopyConnectedComponent cp(Dest,Src,copyGlobal,data,VMap);
    for(size_t i = 0; i < N; i++)
        MapValue(gvs[i],VMap,RF_None,NULL,&cp);
}
#endif



void llvmutil_optimizemodule(Module * M, TargetMachine * TM) {
    PassManager MPM;
    llvmutil_addtargetspecificpasses(&MPM, TM);

    MPM.add(createVerifierPass()); //make sure we haven't messed stuff up yet
    MPM.add(createGlobalDCEPass()); //run this early since anything not in the table of exported functions is still in this module
                                     //this will remove dead functions
    
    PassManagerBuilder PMB;
    PMB.OptLevel = 3;
    PMB.SizeLevel = 0;
    PMB.Inliner = createFunctionInliningPass(PMB.OptLevel, 0);
    
#if LLVM_VERSION >= 35
    PMB.LoopVectorize = true;
    PMB.SLPVectorize = true;
#endif

    PMB.populateModulePassManager(MPM);

    MPM.run(*M);
}

#if LLVM_VERSION >= 34
error_code llvmutil_createtemporaryfile(const Twine &Prefix, StringRef Suffix, SmallVectorImpl<char> &ResultPath) { return sys::fs::createTemporaryFile(Prefix,Suffix,ResultPath); }
#else
error_code llvmutil_createtemporaryfile(const Twine &Prefix, StringRef Suffix, SmallVectorImpl<char> &ResultPath) {
    llvm::sys::Path P("/tmp");
    P.appendComponent(Prefix.str());
    P.appendSuffix(Suffix);
    P.makeUnique(false,NULL);
    StringRef str = P.str();
    ResultPath.append(str.begin(),str.end());
    return error_code();
}
#endif

int llvmutil_executeandwait(LLVM_PATH_TYPE program, const char ** args, std::string * err) {
#if LLVM_VERSION >= 34
    bool executionFailed = false;
    llvm::sys::ProcessInfo Info = llvm::sys::ExecuteNoWait(program,args,0,0,0,err,&executionFailed);
    if(executionFailed)
        return -1;
    #ifndef _WIN32
        //WAR for llvm bug (http://llvm.org/bugs/show_bug.cgi?id=18869)
        pid_t pid;
        int status;
        do {
            pid = waitpid(Info.Pid,&status,0);
        } while(pid == -1 && errno == EINTR);
        if(pid == -1) {
            *err = strerror(errno);
            return -1;
        } else {
            return WEXITSTATUS(status);
        }
    #else
        return llvm::sys::Wait(Info, 0, true, err).ReturnCode;
    #endif
#else
    return sys::Program::ExecuteAndWait(program, args, 0, 0, 0, 0, err);
#endif
}
