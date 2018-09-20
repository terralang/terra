/* See Copyright Notice in ../LICENSE.txt */

#include <stdio.h>

#include "tllvmutil.h"

#if LLVM_VERSION <= 36
#include "llvm/Target/TargetLibraryInfo.h"
#else
#include "llvm/Analysis/TargetLibraryInfo.h"
#endif
#include "llvm/MC/MCAsmInfo.h"
#if LLVM_VERSION < 39
#include "llvm/MC/MCDisassembler.h"
#else
#include "llvm/MC/MCDisassembler/MCDisassembler.h"
#endif
#include "llvm/MC/MCInst.h"
#include "llvm/MC/MCInstPrinter.h"
#include "llvm/MC/MCInstrInfo.h"
#include "llvm/MC/MCRegisterInfo.h"
#include "llvm/MC/MCSubtargetInfo.h"
#if LLVM_VERSION >= 35
#include "llvm/MC/MCContext.h"
#endif
#if LLVM_VERSION < 50
#include "llvm/Support/MemoryObject.h"
#endif
#ifndef _WIN32
#include <sys/wait.h>
#endif

using namespace llvm;

void llvmutil_addtargetspecificpasses(PassManagerBase * fpm, TargetMachine * TM) {
    assert(TM && fpm);
#if LLVM_VERSION >= 37
    TargetLibraryInfoImpl TLII(TM->getTargetTriple());
    fpm->add(new TargetLibraryInfoWrapperPass(TLII));
#else
    TargetLibraryInfo * TLI = new TargetLibraryInfo(Triple(TM->getTargetTriple()));
    fpm->add(TLI);
#endif
#if LLVM_VERSION <= 35
    DataLayout * TD = new DataLayout(*TM->getDataLayout());
#endif
#if LLVM_VERSION <= 34
    fpm->add(TD);
#elif LLVM_VERSION == 35
    fpm->add(new DataLayoutPass(*TD));
#elif LLVM_VERSION == 36
    fpm->add(new DataLayoutPass());
#else
    fpm->add(createTargetTransformInfoWrapperPass(TM->getTargetIRAnalysis()));
#endif
    
#if LLVM_VERSION == 32
    fpm->add(new TargetTransformInfo(TM->getScalarTargetTransformInfo(),
                                     TM->getVectorTargetTransformInfo()));
#elif LLVM_VERSION >= 33 && LLVM_VERSION <= 36
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

#if LLVM_VERSION < 50
struct SimpleMemoryObject : public MemoryObject {
  uint64_t getBase() const { return 0; }
  uint64_t getExtent() const { return ~0ULL; }
  int readByte(uint64_t Addr, uint8_t *Byte) const {
    *Byte = *(uint8_t*)Addr;
    return 0;
  }
};
#endif

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
    MCInstPrinter *IP = TheTarget->createMCInstPrinter(
                                                      #if LLVM_VERSION >= 37
                                                      Triple(TripleName),
                                                      #endif
                                                      AsmPrinterVariant,
                                                     *MAI, *MII, *MRI
                                                     #if LLVM_VERSION <= 36
                                                     , *STI
                                                     #endif
                                                     );
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
        IP->printInst(&Inst,Out,""
        #if LLVM_VERSION >= 37
        , *STI
        #endif
        );
        Out << "\n";
    }
    Out.flush();
    delete MAI; delete MRI; delete STI; delete MII; delete DisAsm; delete IP;
}

//adapted from LLVM's C interface "LLVMTargetMachineEmitToFile"
bool llvmutil_emitobjfile(Module * Mod, TargetMachine * TM, bool outputobjectfile, emitobjfile_t & dest) {

    PassManagerT pass;
    llvmutil_addtargetspecificpasses(&pass, TM);
    
    TargetMachine::CodeGenFileType ft = outputobjectfile? TargetMachine::CGFT_ObjectFile : TargetMachine::CGFT_AssemblyFile;
    
    #if LLVM_VERSION <= 36
    formatted_raw_ostream destf(dest);
    #else
    emitobjfile_t & destf = dest;
    #endif
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
    
    CopyConnectedComponent(Module * dest_, Module * src_, llvmutil_Property copyGlobal_, void * data_, ValueToValueMapTy & VMap_)
    : dest(dest_), src(src_), copyGlobal(copyGlobal_), data(data_), VMap(VMap_) {}
    bool needsFreshlyNamedConstant(GlobalVariable * GV, GlobalVariable * newGV) {
        if(GV->isConstant() && GV->hasPrivateLinkage() &&
#if LLVM_VERSION < 39
           GV->hasUnnamedAddr()
#else
           GV->hasAtLeastLocalUnnamedAddr()
#endif
           ) { //this is a candidate constant
            return !newGV->isConstant() || newGV->getInitializer() != GV->getInitializer(); //it is not equal to its target
        }
        return false;
    }
    #if LLVM_VERSION == 38
    virtual Value * materializeDeclFor(Value * V) {
    #elif LLVM_VERSION < 38
    virtual Value * materializeValueFor(Value * V) {
    #else
    virtual Value * materialize(Value * V) {
    #endif
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
                    VMap[&*I] = &*II;
                }
                VMap[fn] = newfn;
                SmallVector<ReturnInst*,8> Returns;
                CloneFunctionInto(newfn, fn, VMap, true, Returns, "", NULL, NULL, this);
            }else{
                newfn->setLinkage(GlobalValue::ExternalLinkage);
            }
            return newfn;
        } else if(GlobalVariable * GV = dyn_cast<GlobalVariable>(V)) {
            GlobalVariable * newGV = dest->getGlobalVariable(GV->getName(),true);
            if(!newGV || needsFreshlyNamedConstant(GV,newGV)) {
                newGV = new GlobalVariable(*dest,GV->getType()->getElementType(),GV->isConstant(),GV->getLinkage(),NULL,GV->getName(),NULL,GlobalVariable::NotThreadLocal,GV->getType()->getAddressSpace());
                newGV->copyAttributesFrom(GV);
                if(!GV->isDeclaration()) {
                    if(!copyGlobal(GV,data)) {
                        newGV->setLinkage(GlobalValue::ExternalLinkage);
                    } else if(GV->hasInitializer()) {
                        Value * C = MapValue(GV->getInitializer(),VMap,RF_None,NULL,this);
                        newGV->setInitializer(cast<Constant>(C));
                    }
                }
            }
            return newGV;
        } else return materializeValueForMetadata(V);
    }
#ifdef DEBUG_INFO_WORKING
    DIBuilder * DI;
    DICompileUnit NCU;
    void CopyDebugMetadata() {
        DI = NULL;
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
    Value * materializeValueForMetadata(Value * V) {
    #if LLVM_VERSION <= 35
        if(MDNode * MD = dyn_cast<MDNode>(V)) {
            DISubprogram SP(MD);
            if(DI != NULL && SP.isSubprogram()) {
    #else
        if(auto * MDV = dyn_cast<MetadataAsValue>(V)) {
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
#else
    void CopyDebugMetadata() {}
    Value * materializeValueForMetadata(Value * V) { return NULL; }
    void finalize() {}
#endif
    
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
    PassManagerT MPM;
    llvmutil_addtargetspecificpasses(&MPM, TM);

    MPM.add(createVerifierPass()); //make sure we haven't messed stuff up yet
    MPM.add(createGlobalDCEPass()); //run this early since anything not in the table of exported functions is still in this module
                                     //this will remove dead functions
    
    PassManagerBuilder PMB;
    PMB.OptLevel = 3;
    PMB.SizeLevel = 0;
#if LLVM_VERSION < 50
    PMB.Inliner = createFunctionInliningPass(PMB.OptLevel, 0);
#else
    PMB.Inliner = createFunctionInliningPass(PMB.OptLevel, 0, false);
#endif

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
    llvm::sys::ProcessInfo Info = llvm::sys::ExecuteNoWait(program,args,nullptr,{},0,err,&executionFailed);
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
