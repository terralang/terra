/* See Copyright Notice in ../LICENSE.txt */
#include <pthread.h>
#include "tcompiler.h"
#include "tkind.h"
#include "terrastate.h"
extern "C" {
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
}
#include <assert.h>
#include <stdio.h>
#include <inttypes.h>

#ifdef _WIN32
#include <io.h>
#include <time.h>
#include <Windows.h>
#undef interface
#else
#include <unistd.h>
#include <sys/time.h>
#include <sys/wait.h>
#endif

#include <cmath>
#include <sstream>
#include "llvmheaders.h"

#include "tdebug.h"
#include "tcompilerstate.h" //definition of terra_CompilerState which contains LLVM state
#include "tobj.h"
#include "tinline.h"
#include "llvm/Support/ManagedStatic.h"
#include "llvm/ExecutionEngine/MCJIT.h"
#include "llvm/Bitcode/ReaderWriter.h"
#include "llvm/Support/Atomic.h"
#include "llvm/Support/FileSystem.h"
#include "tllvmutil.h"

using namespace llvm;


#define TERRALIB_FUNCTIONS(_) \
    _(codegen,1) /*entry point from lua into compiler to generate LLVM for a function, other functions it calls may not yet exist*/\
    _(optimize,1) /*entry point from lua into compiler to perform optimizations at the function level, passed an entire strongly connected component of functions\
                    all callee's of these functions that are not in this scc have already been optimized*/\
    _(jit,1) /*entry point from lua into compiler to actually invoke the JIT by calling getPointerToFunction*/\
    _(createglobal,1) \
    _(registerexternfunction,1) \
    _(llvmsizeof,1) \
    _(disassemble,1) \
    _(pointertolightuserdata,0) /*because luajit ffi doesn't do this...*/\
    _(gcdebug,0) \
    _(saveobjimpl,1) \
    _(linklibraryimpl,1) \
    _(currenttimeinseconds,0) \
    _(isintegral,0) \
    _(dumpmodule,1)


#define DEF_LIBFUNCTION(nm,isclo) static int terra_##nm(lua_State * L);
TERRALIB_FUNCTIONS(DEF_LIBFUNCTION)
#undef DEF_LIBFUNCTION

#ifdef PRINT_LLVM_TIMING_STATS
static llvm_shutdown_obj llvmshutdownobj;
#endif

struct DisassembleFunctionListener : public JITEventListener {
    terra_State * T;
    DisassembleFunctionListener(terra_State * T_)
    : T(T_) {}
    virtual void NotifyFunctionEmitted (const Function & f, void * data, size_t sz, const EmittedFunctionDetails & EFD) {
        TerraFunctionInfo & fi = T->C->functioninfo[data];
        fi.fn = &f;
        fi.addr = data;
        fi.size = sz;
        DEBUG_ONLY(T) {
            fi.efd = EFD;
        }
    }
#ifdef TERRA_CAN_USE_MCJIT
    virtual void NotifyObjectEmitted(const ObjectImage &Obj) {
        error_code err;
        for(object::symbol_iterator I = Obj.begin_symbols(), E = Obj.end_symbols();
            I != E;
#if LLVM_VERSION <=34
            I.increment(err)
#else
          ++I
#endif
        ) {
            StringRef name;
            err = I->getName(name);
            object::SymbolRef::Type t;
            I->getType(t);
            if(t == object::SymbolRef::ST_Function) {
                uint64_t sz;
                I->getSize(sz);
                #ifndef __arm__
		name = name.substr(1);
                #endif
                Function * F = T->C->m->getFunction(name);
                if(F) {
                    void * addr = (void*) T->C->ee->getFunctionAddress(name);
                    assert(addr);
                    TerraFunctionInfo & fi = T->C->functioninfo[addr];
                    fi.fn = F;
                    fi.addr = addr;
                    fi.size = sz;
                }
            }
        }
    }
#endif
};

static double CurrentTimeInSeconds() {
#ifdef _WIN32
    static uint64_t freq = 0;
    if(freq == 0) {
        LARGE_INTEGER i;
        QueryPerformanceFrequency(&i);
        freq = i.QuadPart;
    }
    LARGE_INTEGER t;
    QueryPerformanceCounter(&t);
    return t.QuadPart / (double) freq;
#else
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec + tv.tv_usec / 1000000.0;
#endif
}
static int terra_currenttimeinseconds(lua_State * L) {
    lua_pushnumber(L, CurrentTimeInSeconds());
    return 1;
}

static void RecordTime(Obj * obj, const char * name, double begin) {
    lua_State * L = obj->getState();
    Obj stats;
    if(obj->obj("stats",&stats)) {
        double end = CurrentTimeInSeconds();
        lua_pushnumber(L, end - begin);
        stats.setfield(name);
    }
}

static void AddLLVMOptions(int N,...) {
    va_list ap;
    va_start(ap, N);
    std::vector<const char *> ops;
    ops.push_back("terra");
    for(int i = 0; i < N; i++) {
        const char * arg = va_arg(ap, const char *);
        ops.push_back(arg);
    }
    cl::ParseCommandLineOptions(N+1, &ops[0]);
}

//useful for debugging GC problems. You can attach it to 
static int terra_gcdebug(lua_State * L) {
    lua_newuserdata(L,sizeof(void*));
    lua_getfield(L,LUA_GLOBALSINDEX,"terra");
    lua_getfield(L,-1,"llvm_gcdebugmetatable");
    lua_setmetatable(L,-3);
    lua_pop(L,1); //the 'terra' table
    lua_setfield(L,-2,"llvm_gcdebughandle");
    return 0;
}

static void RegisterFunction(struct terra_State * T, const char * name, int isclo, lua_CFunction fn) {
    if(isclo) {
        lua_pushlightuserdata(T->L,(void*)T);
        lua_pushcclosure(T->L,fn,1);
    } else {
        lua_pushcfunction(T->L, fn);
    }
    lua_setfield(T->L,-2,name);
}

static llvm::sys::Mutex terrainitlock;
static int terrainitcount;
bool OneTimeInit(struct terra_State * T) {
    bool success = true;
    terrainitlock.acquire();
    terrainitcount++;
    if(terrainitcount == 1) {
        #ifdef PRINT_LLVM_TIMING_STATS
            AddLLVMOptions(1,"-time-passes");
        #endif
#ifndef __arm__
        AddLLVMOptions(1,"-x86-asm-syntax=intel");
#endif
        InitializeNativeTarget();
        InitializeNativeTargetAsmPrinter();
        InitializeNativeTargetAsmParser();
    } else {
        #if LLVM_VERSION <= 34
        if(!llvm_is_multithreaded()) {
            if(!llvm_start_multithreaded()) {
                terra_pusherror(T,"llvm failed to start multi-threading\n");
                success = false;
            }
        }
        #endif //after 3.5, this isn't needed
    }
    terrainitlock.release();
    return success;
}

//LLVM 3.1 doesn't enable avx even if it is present, we detect and force it here
namespace llvm {
    namespace X86_MC {
      bool GetCpuIDAndInfo(unsigned value, unsigned *rEAX,
                           unsigned *rEBX, unsigned *rECX, unsigned *rEDX);
    }
}
bool HostHasAVX() {
#ifdef __arm__
    return false;
#else
    unsigned EAX,EBX,ECX,EDX;
    llvm::X86_MC::GetCpuIDAndInfo(1,&EAX,&EBX,&ECX,&EDX);
    return (ECX >> 28) & 1;
#endif
}

int terra_compilerinit(struct terra_State * T) {
    if(!OneTimeInit(T))
        return LUA_ERRRUN;
    
    
    lua_getfield(T->L,LUA_GLOBALSINDEX,"terra");
    
    #define REGISTER_FN(name,isclo) RegisterFunction(T,#name,isclo,terra_##name);
    TERRALIB_FUNCTIONS(REGISTER_FN)
    #undef REGISTER_FN

    lua_pushnumber(T->L,LLVM_VERSION);
    lua_setfield(T->L,-2, "llvmversion");
    
    lua_pop(T->L,1); //remove terra from stack
    
    T->C = new terra_CompilerState();
    memset(T->C, 0, sizeof(terra_CompilerState));
    JITMemoryManager * JMM = JITMemoryManager::CreateDefaultMemManager();
    
    terra_debuginit(T,JMM);
    
    T->C->next_unused_id = 0;
    T->C->ctx = new LLVMContext();
    
    
    TargetOptions options;
    DEBUG_ONLY(T) {
        options.NoFramePointerElim = true;
    }
    CodeGenOpt::Level OL = CodeGenOpt::Aggressive;
    
    #if LLVM_VERSION >= 33
    std::string Triple = llvm::sys::getProcessTriple();
    #else
    std::string Triple = llvm::sys::getDefaultTargetTriple();
    #endif
    
    std::string CPU = llvm::sys::getHostCPUName();

#ifdef __arm__
    //force MCJIT since old JIT is partially broken on ARM
    //force hard float since we currently onlly work on platforms that have it
    options.FloatABIType = FloatABI::Hard;
    T->options.usemcjit = true;
#endif    


    std::string err;
    const Target *TheTarget = TargetRegistry::lookupTarget(Triple, err);
    TargetMachine * TM = TheTarget->createTargetMachine(Triple, CPU, HostHasAVX() ? "+avx" : "", options,Reloc::PIC_,CodeModel::Default,OL);
    T->C->td = TM->TARGETDATA(get)();
    
    if(T->options.usemcjit) {
#ifndef TERRA_CAN_USE_MCJIT
        terra_pusherror(T, "mcjit is not supported using LLVM %d",LLVM_VERSION);
        return LUA_ERRRUN;
#endif
    }
    
    Module * topeemodule = new Module("terra",*T->C->ctx);
    
    EngineBuilder eb(topeemodule);
    eb.setErrorStr(&err)
      .setMCPU(CPU)
      .setEngineKind(EngineKind::JIT)
      .setAllocateGVsWithCode(false)
      .setUseMCJIT(T->options.usemcjit)
      .setTargetOptions(options)
      .setOptLevel(CodeGenOpt::Aggressive);
    
    if(!T->options.usemcjit) //make sure we don't use JMM for MCJIT, since it will not correctly invalidate icaches on archiectures that need it
        eb.setJITMemoryManager(JMM);
 
    T->C->ee = eb.create();
    
    if (!T->C->ee) {
        terra_pusherror(T,"llvm: %s\n",err.c_str());
        return LUA_ERRRUN;
    }
    
    if(T->options.usemcjit) {
        T->C->m = new Module("terra",*T->C->ctx);
    } else {
        T->C->m = topeemodule;
    }
    T->C->m->setTargetTriple(Triple);
    
    T->C->fpm = new FunctionPassManager(T->C->m);

    llvmutil_addtargetspecificpasses(T->C->fpm, TM);
    llvmutil_addoptimizationpasses(T->C->fpm);
    
    
    if(!TheTarget) {
        terra_pusherror(T,"llvm: %s\n",err.c_str());
        return LUA_ERRRUN;
    }
    
    T->C->tm = TM;
    T->C->mi = new ManualInliner(T->C->tm,T->C->m);
    T->C->jiteventlistener = new DisassembleFunctionListener(T);
    T->C->ee->RegisterJITEventListener(T->C->jiteventlistener);
    
    return 0;
}

int terra_compilerfree(struct terra_State * T) {
    T->C->ee->UnregisterJITEventListener(T->C->jiteventlistener);
    delete T->C->jiteventlistener;
    delete T->C->mi;
    delete T->C->fpm;
    delete T->C->ee;
    delete T->C->tm;
    delete T->C->ctx;
    if(T->C->cwrapperpm)
        delete T->C->cwrapperpm;
    delete T->C;
    return 0;
}

struct TerraCompiler;

static void GetStructEntries(Obj * typ, Obj * entries) {
    Obj layout;
    if(!typ->obj("cachedlayout",&layout)) {
        assert(!"typechecked failed to complete type needed by the compiler, this is a bug.");
    }
    layout.obj("entries",entries);
}

struct TType { //contains llvm raw type pointer and any metadata about it we need
    Type * type;
    bool issigned;
    bool islogical;
    bool incomplete; // does this aggregate type or its children include an incomplete struct
};

class Types {
    terra_State * T;
    terra_CompilerState * C;
    TType * GetIncomplete(Obj * typ) {
        TType * t = NULL;
        if(!LookupTypeCache(typ, &t)) {
            assert(t);
            switch(typ->kind("kind")) {
                case T_pointer: {
                    Obj base;
                    typ->obj("type",&base);
                    TType * baset = GetIncomplete(&base);
                    t->type = PointerType::get(baset->type,typ->number("addressspace"));
                } break;
                case T_array: {
                    Obj base;
                    typ->obj("type",&base);
                    int N = typ->number("N");
                    TType * baset = GetIncomplete(&base);
                    t->type = ArrayType::get(baset->type, N);
                    t->incomplete = baset->incomplete;
                } break;
                case T_struct: {
                    StructType * st = CreateStruct(typ);
                    t->type = st;
                    t->incomplete = st->isOpaque();
                } break;
                case T_functype: {
                    t->type = Type::getInt8Ty(*C->ctx);
                } break;
                case T_vector: {
                    Obj base;
                    typ->obj("type",&base);
                    int N = typ->number("N");
                    TType * ttype = GetIncomplete(&base); //vectors can only contain primitives, so the type must be complete
                    Type * baseType = ttype->type;
                    t->issigned = ttype->issigned;
                    t->islogical = ttype->islogical;
                    t->type = VectorType::get(baseType, N);
                } break;
                case T_primitive: {
                    CreatePrimitiveType(typ, t);
                } break;
                case T_niltype: {
                    t->type = Type::getInt8PtrTy(*C->ctx);
                } break;
                case T_opaque: {
                    t->type = Type::getInt8Ty(*C->ctx);
                } break;
                default: {
                    printf("kind = %d, %s\n",typ->kind("kind"),tkindtostr(typ->kind("kind")));
                    terra_reporterror(T,"type not understood or not primitive\n");
                } break;
            }
        }
        assert(t && t->type);
        return t;
    }
    void CreatePrimitiveType(Obj * typ, TType * t) {
        int bytes = typ->number("bytes");
        switch(typ->kind("type")) {
            case T_float: {
                if(bytes == 4) {
                    t->type = Type::getFloatTy(*C->ctx);
                } else {
                    assert(bytes == 8);
                    t->type = Type::getDoubleTy(*C->ctx);
                }
            } break;
            case T_integer: {
                t->issigned = typ->boolean("signed");
                t->type = Type::getIntNTy(*C->ctx,bytes * 8);
            } break;
            case T_logical: {
                t->type = Type::getInt8Ty(*C->ctx);
                t->islogical = true;
            } break;
            default: {
                printf("kind = %d, %s\n",typ->kind("kind"),tkindtostr(typ->kind("type")));
                terra_reporterror(T,"type not understood");
            } break;
        }
    }
    Type * FunctionPointerType() {
        return Type::getInt8PtrTy(*C->ctx);
    }
    bool LookupTypeCache(Obj * typ, TType ** t) {
        *t = (TType*) typ->ud("llvm_type"); //try to look up the cached type
        if(*t == NULL) {
            *t = (TType*) lua_newuserdata(T->L,sizeof(TType));
            memset(*t,0,sizeof(TType));
            typ->setfield("llvm_type");
            assert(*t != NULL);
            return false;
        }
        return true;
    }
    StructType * CreateStruct(Obj * typ) {
        //check to see if it was initialized externally first
        if(typ->boolean("llvm_definingfunction")) {
            Function * df = C->m->getFunction(typ->string("llvm_definingfunction"));
            int argpos = typ->number("llvm_argumentposition");
            StructType * st = cast<StructType>(df->getFunctionType()->getParamType(argpos)->getPointerElementType());
            assert(st);
            return st;
        }
        std::string name = typ->asstring("name");
        bool isreserved = beginsWith(name, "struct.") || beginsWith(name, "union.");
        name = (isreserved) ? std::string("$") + name : name;
        return StructType::create(*C->ctx, name);
    }
    bool beginsWith(const std::string & s, const std::string & prefix) {
        return s.substr(0,prefix.size()) == prefix;
    }
    void LayoutStruct(StructType * st, Obj * typ) {
        Obj layout;
        GetStructEntries(typ,&layout);
        int N = layout.size();
        std::vector<Type *> entry_types;
        
        unsigned unionAlign = 0; //minimum union alignment
        Type * unionType = NULL; //type with the largest alignment constraint
        size_t unionAlignSz = 0; //size of type with largest alignment contraint
        size_t unionSz   = 0;    //allocation size of the largest member
                                 
        for(int i = 0; i < N; i++) {
            Obj v;
            layout.objAt(i, &v);
            Obj vt;
            v.obj("type",&vt);
            
            Type * fieldtype = Get(&vt)->type;
            bool inunion = v.boolean("inunion");
            if(inunion) {
                unsigned align = C->td->getABITypeAlignment(fieldtype);
                if(align >= unionAlign) { // orequal is to make sure we have a non-null type even if it is a 0-sized struct
                    unionAlign = align;
                    unionType = fieldtype;
                    unionAlignSz = C->td->getTypeAllocSize(fieldtype);
                }
                size_t allocSize = C->td->getTypeAllocSize(fieldtype);
                if(allocSize > unionSz)
                    unionSz = allocSize;
                
                //check if this is the last member of the union, and if it is, add it to our struct
                Obj nextObj;
                if(i + 1 < N)
                    layout.objAt(i+1,&nextObj);
                if(i + 1 == N || nextObj.number("allocation") != v.number("allocation")) {
                    std::vector<Type *> union_types;
                    assert(unionType);
                    union_types.push_back(unionType);
                    if(unionAlignSz < unionSz) { // the type with the largest alignment requirement is not the type with the largest size, pad this struct so that it will fit the largest type
                        size_t diff = unionSz - unionAlignSz;
                        union_types.push_back(ArrayType::get(Type::getInt8Ty(*C->ctx),diff));
                    }
                    entry_types.push_back(StructType::get(*C->ctx,union_types));
                    unionAlign = 0;
                    unionType = NULL;
                    unionAlignSz = 0;
                    unionSz = 0;
                }
            } else {
                entry_types.push_back(fieldtype);
            }
        }
        st->setBody(entry_types);
        VERBOSE_ONLY(T) {
            printf("Struct Layout Is:\n");
            st->dump();
            printf("\nEnd Layout\n");
        }
    }
public:
    Types(terra_State * T_) : T(T_), C(T_->C) {}
    TType * Get(Obj * typ) {
        assert(typ->kind("kind") != T_functype); // Get should not be called on function directly, only function pointers
        TType * t = GetIncomplete(typ);
        if(t->incomplete) {
            assert(t->type->isAggregateType());
            switch(typ->kind("kind")) {
                case T_struct: {
                    LayoutStruct(cast<StructType>(t->type), typ);
                } break;
                case T_array: {
                    Obj base;
                    typ->obj("type",&base);
                    Get(&base); //force base type to be completed
                } break;
                default:
                    terra_reporterror(T,"type marked incomplete is not an array or struct\n");
            }
        }
        t->incomplete = false;
        return t;
    }
    bool IsUnitType(Obj * t) {
        t->pushfield("isunit");
        t->push();
        lua_call(T->L,1,1);
        bool result = lua_toboolean(T->L,-1);
        lua_pop(T->L,1);
        return result;
    }
    void EnsureTypeIsComplete(Obj * typ) {
        Get(typ);
    }
    void EnsurePointsToCompleteType(Obj * ptrTy) {
        if(ptrTy->kind("kind") == T_pointer) {
            Obj objTy;
            ptrTy->obj("type",&objTy);
            EnsureTypeIsComplete(&objTy);
        } //otherwise it is niltype and already complete
    }
};

//helper function to alloca at the beginning of function
static AllocaInst *CreateAlloca(IRBuilder<> * B, Type *Ty, Value *ArraySize = 0, const Twine &Name = "") {
    BasicBlock * entry = &B->GetInsertBlock()->getParent()->getEntryBlock();
    IRBuilder<> TmpB(entry,
                     entry->begin()); //make sure alloca are at the beginning of the function
                                      //this is needed because alloca's that do not dominate the
                                      //function do weird things
    return TmpB.CreateAlloca(Ty,ArraySize,Name);
}


//functions that handle the details of the x86_64 ABI (this really should be handled by LLVM...)
struct CCallingConv {
    terra_State * T;
    lua_State * L;
    terra_CompilerState * C;
    Types * Ty;
    IRBuilder<> * B;
    
    CCallingConv(terra_State * T_, Types * Ty_, IRBuilder<> * B_) : T(T_), L(T_->L), C(T_->C), Ty(Ty_), B(B_) {}
    
    enum RegisterClass {
        C_INTEGER,
        C_NO_CLASS,
        C_SSE,
        C_MEMORY
    };
    
    enum ArgumentKind {
        C_PRIMITIVE, //passed without modifcation (i.e. any non-aggregate type)
        C_AGGREGATE_REG, //aggregate passed through registers
        C_AGGREGATE_MEM, //aggregate passed through memory
    };
    
    struct Argument {
        ArgumentKind kind;
        TType * type; //orignal type for the object
        Type * cctype; //if type == C_AGGREGATE_REG, this is a struct that holds a list of the values that goes into the registers
                       //if type == CC_PRIMITIVE, this is the struct that this type appear in the argument list and the type should be coerced to
        Argument() {}
        Argument(ArgumentKind kind, TType * type, Type * cctype = NULL) {
            this->kind = kind;
            this->type = type;
            this->cctype = cctype ? cctype : type->type;
        }
        int GetNumberOfTypesInParamList() {
            if(C_AGGREGATE_REG == this->kind)
                return cast<StructType>(this->cctype)->getNumElements();
            return 1;
        }
    };
    
    struct Classification {
        Argument returntype;
        std::vector<Argument> paramtypes;
        FunctionType * fntype;
    };
    
    RegisterClass Meet(RegisterClass a, RegisterClass b) {
        switch(a) {
            case C_INTEGER:
                switch(b) {
                    case C_INTEGER: case C_NO_CLASS: case C_SSE:
                        return C_INTEGER;
                    case C_MEMORY:
                        return C_MEMORY;
                }
            case C_SSE:
                switch(b) {
                    case C_INTEGER:
                        return C_INTEGER;
                    case C_NO_CLASS: case C_SSE:
                        return C_SSE;
                    case C_MEMORY:
                        return C_MEMORY;
                }
            case C_NO_CLASS:
                return b;
            case C_MEMORY:
                return C_MEMORY;
        }
    }
    
    void MergeValue(RegisterClass * classes, size_t offset, Obj * type) {
        Type * t = Ty->Get(type)->type;
        int entry = offset / 8;
        if(t->isVectorTy()) //we don't handle structures with vectors in them yet
            classes[entry] = C_MEMORY;
        else if(t->isFloatingPointTy())
            classes[entry] = Meet(classes[entry],C_SSE);
        else if(t->isIntegerTy() || t->isPointerTy())
            classes[entry] = Meet(classes[entry],C_INTEGER);
        else if(t->isStructTy()) {
            StructType * st = cast<StructType>(Ty->Get(type)->type);
            assert(!st->isOpaque());
            const StructLayout * sl = C->td->getStructLayout(st);
            Obj layout;
            GetStructEntries(type,&layout);
            int N = layout.size();
            for(int i = 0; i < N; i++) {
                Obj entry;
                layout.objAt(i,&entry);
                int allocation = entry.number("allocation");
                size_t structoffset = sl->getElementOffset(allocation);
                Obj entrytype;
                entry.obj("type",&entrytype);
                MergeValue(classes, offset + structoffset, &entrytype);
            }
        } else if(t->isArrayTy()) {
            ArrayType * at = cast<ArrayType>(Ty->Get(type)->type);
            size_t elemsize = C->td->getTypeAllocSize(at->getElementType());
            size_t sz = at->getNumElements();
            Obj elemtype;
            type->obj("type", &elemtype);
            for(size_t i = 0; i < sz; i++)
                MergeValue(classes, offset + i * elemsize, &elemtype);
        } else
            assert(!"unexpected value in classification");
    }
#ifndef _WIN32
    Type * TypeForClass(size_t size, RegisterClass clz) {
        switch(clz) {
             case C_SSE:
                switch(size) {
                    case 4: return Type::getFloatTy(*C->ctx);
                    case 8: return Type::getDoubleTy(*C->ctx);
                    default: assert(!"unexpected size for floating point class");
                }
            case C_INTEGER:
                assert(size <= 8);
                return Type::getIntNTy(*C->ctx, size * 8);
            default:
                assert(!"unexpected class");
        }
    }
    bool ValidAggregateSize(size_t sz) {
        return sz <= 16;
    }
#else
    Type * TypeForClass(size_t size, RegisterClass clz) {
        assert(size <= 8);
        return Type::getIntNTy(*C->ctx, size * 8); 
    }
    bool ValidAggregateSize(size_t sz) {
        bool isPow2 = sz && !(sz & (sz - 1));
        return sz <= 8 && isPow2;
    }
#endif
    
    Argument ClassifyArgument(Obj * type, int * usedfloat, int * usedint) {
        TType * t = Ty->Get(type);
        
        if(!t->type->isAggregateType()) {
            if(t->type->isFloatingPointTy() || t->type->isVectorTy())
                ++*usedfloat;
            else
                ++*usedint;
            bool usei1 = t->islogical && !t->type->isVectorTy();
            return Argument(C_PRIMITIVE,t,usei1 ? Type::getInt1Ty(*C->ctx) : NULL);
        }
        
        int sz = C->td->getTypeAllocSize(t->type);
        if(!ValidAggregateSize(sz)) {
            return Argument(C_AGGREGATE_MEM,t);
        }
        
        RegisterClass classes[] = {C_NO_CLASS, C_NO_CLASS};
        
        int sizes[] = { std::min(sz,8), std::max(0,sz - 8) };
        MergeValue(classes, 0, type);
        if(classes[0] == C_MEMORY || classes[1] == C_MEMORY) {
            return Argument(C_AGGREGATE_MEM,t);
        }
        int nfloat = (classes[0] == C_SSE) + (classes[1] == C_SSE);
        int nint = (classes[0] == C_INTEGER) + (classes[1] == C_INTEGER);
        if (sz > 8 && (*usedfloat + nfloat > 8 || *usedint + nint > 6)) {
            return Argument(C_AGGREGATE_MEM,t);
        }
        
        *usedfloat += nfloat;
        *usedint += nint;
        
        std::vector<Type*> elements;
        for(int i = 0; i < 2; i++)
            if(sizes[i] > 0)
                elements.push_back(TypeForClass(sizes[i], classes[i]));
        
        return Argument(C_AGGREGATE_REG,t,
                        StructType::get(*C->ctx,elements));
    }
    void Classify(Obj * ftype, Obj * params, Classification * info) {
        Obj returntype;
        ftype->obj("returntype",&returntype);
        int zero = 0;
        info->returntype = ClassifyArgument(&returntype, &zero, &zero);
        
        #ifdef _WIN32
        //windows classifies empty structs as pass by pointer, but we need a return value of unit (an empty tuple)
        //to be translated to void. So if it is unit, force the return value to be void by overriding the normal 
        //classification decision
        if(Ty->IsUnitType(&returntype)) {
            info->returntype = Argument(C_AGGREGATE_REG,info->returntype.type,StructType::get(*C->ctx));
        }
        #endif
        
        int nfloat = 0;
        int nint = info->returntype.kind == C_AGGREGATE_MEM ? 1 : 0; /*sret consumes RDI for the return value pointer so it counts towards the used integer registers*/
        int N = params->size();
        for(int i = 0; i < N; i++) {
            Obj elem;
            params->objAt(i,&elem);
            info->paramtypes.push_back(ClassifyArgument(&elem,&nfloat,&nint));
        }
        info->fntype = CreateFunctionType(info,ftype->boolean("isvararg"));
    }
    
    Classification * ClassifyFunction(Obj * fntyp) {
        Classification * info  = (Classification*) fntyp->ud("llvm_ccinfo");
        if(!info) {
            info = new Classification();
            lua_pushlightuserdata(L,info);
            
            Obj params;
            fntyp->obj("parameters",&params);
            Classify(fntyp, &params, info);
            Classification * oldinfo = (Classification*) fntyp->ud("llvm_ccinfo");
            assert(!oldinfo);
            fntyp->setfield("llvm_ccinfo");
        }
        return info;
    }
    
    template<typename FnOrCall>
    void addSRetAttr(FnOrCall * r, int idx) {
        #if LLVM_VERSION == 32
            AttrBuilder builder;
            builder.addAttribute(Attributes::StructRet);
            builder.addAttribute(Attributes::NoAlias);
            r->addAttribute(idx,Attributes::get(*C->ctx,builder));
        #elif LLVM_VERSION == 31
            r->addAttribute(idx,Attributes(Attribute::StructRet | Attribute::NoAlias));
        #else
            r->addAttribute(idx,Attribute::StructRet);
            r->addAttribute(idx,Attribute::NoAlias);
        #endif
    }
    template<typename FnOrCall>
    void addByValAttr(FnOrCall * r, int idx) {
        #if LLVM_VERSION == 32
            AttrBuilder builder;
            builder.addAttribute(Attributes::ByVal);
            r->addAttribute(idx,Attributes::get(*C->ctx,builder));
        #elif LLVM_VERSION == 31
            r->addAttribute(idx,Attributes(Attribute::ByVal));
        #else
            r->addAttribute(idx,Attribute::ByVal);
        #endif
    }
    template<typename FnOrCall>
    void addExtAttrIfNeeded(TType * t, FnOrCall * r, int idx) {
        if(!t->type->isIntegerTy() || t->type->getPrimitiveSizeInBits() >= 32)
            return;
        #if LLVM_VERSION == 32
            AttrBuilder builder;
            builder.addAttribute(t->issigned ? Attributes::SExt : Attributes::ZExt);
            r->addAttribute(idx,Attributes::get(*C->ctx,builder));
        #elif LLVM_VERSION == 31
            r->addAttribute(idx,Attributes(t->issigned ? Attribute::SExt : Attribute::ZExt));
        #else
            r->addAttribute(idx,t->issigned ? Attribute::SExt : Attribute::ZExt);
        #endif
    }
    
    template<typename FnOrCall>
    void AttributeFnOrCall(FnOrCall * r, Classification * info) {
        addExtAttrIfNeeded(info->returntype.type, r, 0);
        int argidx = 1;
        if(info->returntype.kind == C_AGGREGATE_MEM) {
            addSRetAttr(r, argidx);
            argidx++;
        }
        for(size_t i = 0; i < info->paramtypes.size(); i++) {
            Argument * v = &info->paramtypes[i];
            if(v->kind == C_AGGREGATE_MEM) {
                #ifndef _WIN32
                addByValAttr(r, argidx);
                #endif
            }
            addExtAttrIfNeeded(v->type, r, argidx);
            argidx += v->GetNumberOfTypesInParamList();
        }
    }
    
    Function * CreateFunction(Obj * ftype, const Twine & name) {
        Classification * info = ClassifyFunction(ftype);
        Function * fn = Function::Create(info->fntype, Function::ExternalLinkage, name, C->m);
        AttributeFnOrCall(fn,info);
        return fn;
    }
    
    PointerType * Ptr(Type * t) {
        return PointerType::getUnqual(t);
    }
    Value * ConvertPrimitive(Value * src, Type * dstType, bool issigned) {
        if(!dstType->isIntegerTy())
            return src;
        return B->CreateIntCast(src, dstType, issigned);
    }
    void EmitEntry(Obj * ftype, Function * func, std::vector<Value *> * variables) {
        Classification * info = ClassifyFunction(ftype);
        assert(info->paramtypes.size() == variables->size());
        Function::arg_iterator ai = func->arg_begin();
        if(info->returntype.kind == C_AGGREGATE_MEM)
            ++ai; //first argument is the return structure, skip it when loading arguments
        for(size_t i = 0; i < variables->size(); i++) {
            Argument * p = &info->paramtypes[i];
            Value * v = (*variables)[i];
            switch(p->kind) {
                case C_PRIMITIVE: {
                    Value * a = ConvertPrimitive(ai,p->type->type,p->type->issigned);
                    B->CreateStore(a,v);
                    ++ai;
                } break;
                case C_AGGREGATE_MEM:
                    //TODO: check that LLVM optimizes this copy away
                    B->CreateStore(B->CreateLoad(ai),v);
                    ++ai;
                    break;
                case C_AGGREGATE_REG: {
                    Value * dest = B->CreateBitCast(v,Ptr(p->cctype));
                    int N = p->GetNumberOfTypesInParamList();
                    for(int j = 0; j < N; j++) {
                        B->CreateStore(ai,B->CreateConstGEP2_32(dest, 0, j));
                        ++ai;
                    }
                } break;
            }
        }
    }
    void EmitReturn(Obj * ftype, Function * function, Value * result) {
        Classification * info = ClassifyFunction(ftype);
        ArgumentKind kind = info->returntype.kind;
        
        if(C_AGGREGATE_REG == kind && info->returntype.GetNumberOfTypesInParamList() == 0) {
            B->CreateRetVoid();
        } else if(C_PRIMITIVE == kind) {
            B->CreateRet(ConvertPrimitive(result,info->returntype.cctype,info->returntype.type->issigned));
        } else if(C_AGGREGATE_MEM == kind) {
            B->CreateStore(result,function->arg_begin());
            B->CreateRetVoid();
        } else if(C_AGGREGATE_REG == kind) {
            Value * dest = CreateAlloca(B,info->returntype.type->type);
            B->CreateStore(result,dest);
            Value *  result = B->CreateBitCast(dest,Ptr(info->returntype.cctype));
            if(info->returntype.GetNumberOfTypesInParamList() == 1)
                result = B->CreateConstGEP2_32(result, 0, 0);
            B->CreateRet(B->CreateLoad(result));
        } else {
            assert(!"unhandled return value");
        }
    }
    
    Value * EmitCall(Obj * ftype, Obj * paramtypes, Value * callee, std::vector<Value*> * actuals) {
        Classification info;
        Classify(ftype,paramtypes,&info);
        
        std::vector<Value*> arguments;
        
        if(C_AGGREGATE_MEM == info.returntype.kind) {
            arguments.push_back(CreateAlloca(B,info.returntype.type->type));
        }
        
        for(size_t i = 0; i < info.paramtypes.size(); i++) {
            Argument * a = &info.paramtypes[i];
            Value * actual = (*actuals)[i];
            switch(a->kind) {
                case C_PRIMITIVE:
                    arguments.push_back(ConvertPrimitive(actual,a->cctype,a->type->issigned));
                    break;
                case C_AGGREGATE_MEM: {
                    Value * scratch = CreateAlloca(B,a->type->type);
                    B->CreateStore(actual,scratch);
                    arguments.push_back(scratch);
                } break;
                case C_AGGREGATE_REG: {
                    Value * scratch = CreateAlloca(B,a->type->type);
                    B->CreateStore(actual,scratch);
                    Value * casted = B->CreateBitCast(scratch,Ptr(a->cctype));
                    int N = a->GetNumberOfTypesInParamList();
                    for(int j = 0; j < N; j++) {
                        arguments.push_back(B->CreateLoad(B->CreateConstGEP2_32(casted,0,j)));
                    }
                } break;
            }
            
        }
        
        //emit call
        //function pointers are stored as &int8 to avoid calling convension issues
        //cast it back to the real pointer type right before calling it
        callee = B->CreateBitCast(callee,Ptr(info.fntype));
        CallInst * call = B->CreateCall(callee, arguments);
        //annotate call with byval and sret
        AttributeFnOrCall(call,&info);
        
        //unstage results
        if(C_PRIMITIVE == info.returntype.kind) {
            return ConvertPrimitive(call,info.returntype.type->type,info.returntype.type->issigned);
        } else {
            Value * aggregate;
            if(C_AGGREGATE_MEM == info.returntype.kind) {
                aggregate = arguments[0];
            } else { //C_AGGREGATE_REG
                aggregate = CreateAlloca(B,info.returntype.type->type);
                Value * casted = B->CreateBitCast(aggregate,Ptr(info.returntype.cctype));
                if(info.returntype.GetNumberOfTypesInParamList() == 1)
                    casted = B->CreateConstGEP2_32(casted, 0, 0);
                if(info.returntype.GetNumberOfTypesInParamList() > 0)
                    B->CreateStore(call,casted);
            }
            return B->CreateLoad(aggregate);
        }
    }
    FunctionType * CreateFunctionType(Classification * info, bool isvararg) {
        std::vector<Type*> arguments;
        
        Type * rt = NULL;
        switch(info->returntype.kind) {
            case C_AGGREGATE_REG: {
                switch(info->returntype.GetNumberOfTypesInParamList()) {
                    case 0: rt = Type::getVoidTy(*C->ctx); break;
                    case 1: rt = cast<StructType>(info->returntype.cctype)->getElementType(0); break;
                    default: rt = info->returntype.cctype; break;
                }
            } break;
            case C_AGGREGATE_MEM: {
                rt = Type::getVoidTy(*C->ctx);
                arguments.push_back(Ptr(info->returntype.type->type));
            } break;
            case C_PRIMITIVE: {
                rt = info->returntype.cctype;
            } break;
        }
        
        for(size_t i = 0; i < info->paramtypes.size(); i++) {
            Argument * a = &info->paramtypes[i];
            switch(a->kind) {
                case C_PRIMITIVE: {
                    arguments.push_back(a->cctype);
                } break;
                case C_AGGREGATE_MEM:
                    arguments.push_back(Ptr(a->type->type));
                    break;
                case C_AGGREGATE_REG: {
                    int N = a->GetNumberOfTypesInParamList();
                    for(int j = 0; j < N; j++) {
                        arguments.push_back(cast<StructType>(a->cctype)->getElementType(j));
                    }
                } break;
            }
        }
        
        return FunctionType::get(rt,arguments,isvararg);
    }
};

static Constant * GetConstant(terra_State * T, Obj * v) {
    lua_State * L = T->L;
    terra_CompilerState * C = T->C;
    Obj t;
    v->obj("type", &t);
    TType * typ = Types(T).Get(&t);
    ConstantFolder B;
    if(typ->type->isAggregateType()) { //if the constant is a large value, we make a single global variable that holds that value
        Type * ptyp = PointerType::getUnqual(typ->type);
        GlobalVariable * gv = (GlobalVariable*) v->ud("llvm_value");
        if(gv == NULL) {
            v->pushfield("object");
            const void * data = lua_topointer(L,-1);
            assert(data);
            lua_pop(L,1); // remove pointer
            size_t size = C->td->getTypeAllocSize(typ->type);
            size_t align = C->td->getPrefTypeAlignment(typ->type);
            Constant * arr = ConstantDataArray::get(*C->ctx,ArrayRef<uint8_t>((const uint8_t*)data,size));
            gv = new GlobalVariable(*C->m, arr->getType(),
                                    true, GlobalValue::ExternalLinkage,
                                    arr, "const");
            gv->setAlignment(align);
            gv->setUnnamedAddr(true);
            lua_pushlightuserdata(L,gv);
            v->setfield("llvm_value");
        }
        return B.CreateBitCast(gv, ptyp);
    } else {
        //otherwise translate the value to LLVM
        v->pushfield("object");
        const void * data = lua_topointer(L,-1);
        assert(data);
        lua_pop(L,1); // remove pointer
        size_t size = C->td->getTypeAllocSize(typ->type);
        if(typ->type->isIntegerTy()) {
            uint64_t integer = 0;
            memcpy(&integer,data,size); //note: assuming little endian, there is probably a better way to do this
            return ConstantInt::get(typ->type, integer);
        } else if(typ->type->isFloatTy()) {
            return ConstantFP::get(typ->type, *(const float*)data);
        } else if(typ->type->isDoubleTy()) {
            return ConstantFP::get(typ->type, *(const double*)data);
        } else if(typ->type->isPointerTy()) {
            Constant * ptrint = ConstantInt::get(C->td->getIntPtrType(*C->ctx), *(const intptr_t*)data);
            return ConstantExpr::getIntToPtr(ptrint, typ->type);
        } else {
            typ->type->dump();
            printf("NYI - constant load\n");
            abort();
        }
    }
}


static GlobalVariable * GetGlobalVariable(terra_State * T, Obj * global, const char * name) {
    GlobalVariable * gv = (GlobalVariable *) global->ud("llvm_value");
    if (gv == NULL) {
        Obj t;
        global->obj("type",&t);
        Type * typ = Types(T).Get(&t)->type;
        
        Constant * llvmconstant = UndefValue::get(typ);
        Obj constant;
        if(global->obj("initializer",&constant)) {
            llvmconstant = GetConstant(T,&constant);
        }
        int as = global->number("addressspace");
        gv = new GlobalVariable(*T->C->m, typ, false, GlobalValue::ExternalLinkage, llvmconstant, name, NULL,
                            #if LLVM_VERSION == 31
                                false,
                            #else
                                GlobalVariable::NotThreadLocal, 
                            #endif
                                as);
        lua_pushlightuserdata(T->L, gv);
        global->setfield("llvm_value");
    }
    return gv;
}


static int terra_deletefunction(lua_State * L);

struct TerraCompiler {
    terra_State * T;
    lua_State * L;
    terra_CompilerState * C;
    IRBuilder<> * B;
    Types Ty;
    CCallingConv CC;
    
    DIBuilder * DB;
    DISubprogram SP;
    StringMap<MDNode*> filenamecache; //map from filename to lexical scope object representing file.
    const char * customfilename;
    int customlinenumber;
    
    Obj * funcobj;
    Function * func;
    std::vector<BasicBlock *> deferred;
    
    TType * getType(Obj * v) {
        return Ty.Get(v);
    }
    TType * typeOfValue(Obj * v) {
        Obj t;
        v->obj("type",&t);
        return getType(&t);
    }
    
    AllocaInst * allocVar(Obj * v) {
        AllocaInst * a = CreateAlloca(B,typeOfValue(v)->type,0,v->asstring("name"));
        lua_pushlightuserdata(L,a);
        v->setfield("value");
        return a;
    }
    
    void getOrCreateFunction(Obj * funcobj, Function ** rfn) {
        Function * fn = (Function *) funcobj->ud("llvm_value");
        Obj ftype;
        funcobj->obj("type",&ftype);
        if(!fn) {
            const char * name = funcobj->string("name");
        
            //function name is $+name so that it can't conflict with any symbols imported from the C namespace
            fn = CC.CreateFunction(&ftype, Twine(StringRef("$"),name));
            
            if(funcobj->hasfield("alwaysinline")) {
                if(funcobj->boolean("alwaysinline")) {
                    fn->ADDFNATTR(AlwaysInline);
                } else {
                    fn->ADDFNATTR(NoInline);
                }
            }
            lua_pushlightuserdata(L,fn);
            funcobj->setfield("llvm_value");

            //attach a userdata object to the function that will call terra_deletefunction 
            //when the function variant is GC'd in lua
            Function** gchandle = (Function**) lua_newuserdata(L,sizeof(Function**));
            *gchandle = fn;
            if(luaL_newmetatable(L,"terra_gcfuncdefinition")) {
                lua_pushlightuserdata(L,(void*)T);
                lua_pushcclosure(L,terra_deletefunction,1);
                lua_setfield(L,-2,"__gc");
            }
            lua_setmetatable(L,-2);
            funcobj->setfield("llvm_gchandle");
            T->numlivefunctions++;
        }
        *rfn = fn;
    }
    
    TerraCompiler(terra_State * T_, Obj * funcobj_) : T(T_), L(T_->L), C(T_->C), B(new IRBuilder<>(*T_->C->ctx)), Ty(T_), CC(T_,&Ty,B), funcobj(funcobj_) {
        double begin = CurrentTimeInSeconds();
        
        getOrCreateFunction(funcobj,&func);
        
        BasicBlock * entry = BasicBlock::Create(*C->ctx,"entry",func);
        
        B->SetInsertPoint(entry);
        
        Obj typedtree;
        Obj parameters;
        
        funcobj->obj("typedtree",&typedtree);
        initDebug(typedtree.string("filename"),typedtree.number("linenumber"));
        setDebugPoint(&typedtree);
        typedtree.obj("parameters",&parameters);
        
        Obj ftype;
        funcobj->obj("type",&ftype);
        
        std::vector<Value *> parametervars;
        emitExpressionList(&parameters, false, &parametervars);
        CC.EmitEntry(&ftype, func, &parametervars);
         
        Obj body;
        typedtree.obj("body",&body);
        emitStmt(&body);
        //if there no terminating return statment, we need to insert one
        //if there was a Return, then this block is dead and will be cleaned up
        emitReturnUndef();
        
        VERBOSE_ONLY(T) {
            func->dump();
        }
        verifyFunction(*func);
        
        RecordTime(funcobj, "llvmgen", begin);
        delete B;
        endDebug();
    }
    
    Value * emitAddressOf(Obj * exp) {
        Value * v = emitExp(exp,false);
        if(exp->boolean("lvalue"))
            return v;
        Value * addr = CreateAlloca(B,typeOfValue(exp)->type);
        B->CreateStore(v,addr);
        return addr;
    }
    
    Value * emitUnary(Obj * exp, Obj * ao) {
        T_Kind kind = exp->kind("operator");
        if (T_addressof == kind)
            return emitAddressOf(ao);
        
        TType * t = typeOfValue(exp);
        Type * baseT = getPrimitiveType(t);
        Value * a = emitExp(ao);
        switch(kind) {
            case T_dereference:
                return a; /* no-op, a is a pointer and lvalue is true for this expression */
                break;
            case T_not:
                if(t->islogical)
                    return B->CreateZExt(B->CreateICmpEQ(a, ConstantInt::get(t->type,0)), t->type);
                else
                    return B->CreateNot(a);
                break;
            case T_sub:
                if(baseT->isIntegerTy()) {
                    return B->CreateNeg(a);
                } else {
                    return B->CreateFNeg(a);
                }
                break;
            default:
                printf("NYI - unary %s\n",tkindtostr(kind));
                abort();
                break;
        }
    }
    Value * emitCompare(T_Kind op, TType * t, Value * a, Value * b) {
        Type * baseT = getPrimitiveType(t);
#define RETURN_OP(op) \
if(baseT->isIntegerTy() || t->type->isPointerTy()) { \
    return B->CreateICmp(CmpInst::ICMP_##op,a,b); \
} else { \
    return B->CreateFCmp(CmpInst::FCMP_O##op,a,b); \
}
#define RETURN_SOP(op) \
if(baseT->isIntegerTy() || t->type->isPointerTy()) { \
    if(t->issigned) { \
        return B->CreateICmp(CmpInst::ICMP_S##op,a,b); \
    } else { \
        return B->CreateICmp(CmpInst::ICMP_U##op,a,b); \
    } \
} else { \
    return B->CreateFCmp(CmpInst::FCMP_O##op,a,b); \
}
        
        switch(op) {
            case T_ne: RETURN_OP(NE) break;
            case T_eq: RETURN_OP(EQ) break;
            case T_lt: RETURN_SOP(LT) break;
            case T_gt: RETURN_SOP(GT) break;
            case T_ge: RETURN_SOP(GE) break;
            case T_le: RETURN_SOP(LE) break;
            default: 
                assert(!"unknown op");
                return NULL;
                break;
        }
#undef RETURN_OP
#undef RETURN_SOP
    }
    void emitBranchOnExpr(Obj * expr, BasicBlock * trueblock, BasicBlock * falseblock) {
        //try to optimize the branching by looking into lazy logical expressions and simplifying them
        T_Kind kind = expr->kind("kind");
        if(T_operator == kind) {
            T_Kind op = expr->kind("operator");
            Obj operands;
            expr->obj("operands",&operands);
            Obj lhs; Obj rhs;
            operands.objAt(0,&lhs);
            operands.objAt(1,&rhs);
            if(T_not == op) {
                emitBranchOnExpr(&lhs, falseblock, trueblock);
                return;
            }
            if(T_and == op || T_or == op) {
                bool isand = T_and == op;
                BasicBlock * condblock = createAndInsertBB((isand) ? "and.lhs.true" : "or.lhs.false");
                emitBranchOnExpr(&lhs, (isand) ? condblock : trueblock, (isand) ? falseblock : condblock);
                setInsertBlock(condblock);
                emitBranchOnExpr(&rhs, trueblock, falseblock);
                return;
            }
        }
        //if no optimizations applied just emit the naive branch
        B->CreateCondBr(emitCond(expr), trueblock, falseblock);
    }
    Value * emitLazyLogical(TType * t, Obj * ao, Obj * bo, bool isAnd) {
        /*
        AND (isAnd == true)
        bool result;
        bool a = <a>;
        if(a) {
            result = <b>;
        } else {
            result = a;
        }
        OR
        bool result;
        bool a = <a>;
        if(a) {
            result = a;
        } else {
            result = <b>;
        }
        */
        
        BasicBlock * stmtB = createAndInsertBB((isAnd) ? "and.rhs" : "or.rhs");
        BasicBlock * mergeB = createAndInsertBB((isAnd) ? "and.end" : "or.end");
        
        emitBranchOnExpr(ao, (isAnd) ? stmtB : mergeB, (isAnd) ? mergeB : stmtB);
        
        Type * int1 = Type::getInt1Ty(*C->ctx);
        setInsertBlock(mergeB);
        PHINode * result = B->CreatePHI(int1, 2);
        Value * literal = ConstantInt::get(int1, !isAnd);
        for(pred_iterator it = pred_begin(mergeB), end = pred_end(mergeB);
            it != end; ++it)
            result->addIncoming(literal,*it);
        
        setInsertBlock(stmtB);
        Value * b = emitCond(bo);
        stmtB = B->GetInsertBlock();
        B->CreateBr(mergeB);
        followsBB(mergeB);
        setInsertBlock(mergeB);
        result->addIncoming(b, stmtB);
        return B->CreateZExt(result, t->type);
    }
    Value * emitIndex(TType * ftype, int tobits, Value * number) {
        TType ttype;
        memset(&ttype,0,sizeof(ttype));
        ttype.type = Type::getIntNTy(*C->ctx,tobits);
        ttype.issigned = ftype->issigned;
        return emitPrimitiveCast(ftype,&ttype,number);
    }
    Value * emitPointerArith(T_Kind kind, Value * pointer, TType * numTy, Value * number) {
        number = emitIndex(numTy,64,number);
        if(kind == T_add) {
            return B->CreateGEP(pointer,number);
        } else if(kind == T_sub) {
            Value * numNeg = B->CreateNeg(number);
            return B->CreateGEP(pointer,numNeg);
        } else {
            assert(!"unexpected pointer arith");
            return NULL;
        }
    }
    Value * emitPointerSub(TType * t, Value * a, Value * b) {
        return B->CreatePtrDiff(a, b);
    }
    Value * emitBinary(Obj * exp, Obj * ao, Obj * bo) {
        TType * t = typeOfValue(exp);
        T_Kind kind = exp->kind("operator");

        //check for lazy operators before evaluateing arguments
        if(t->islogical && !t->type->isVectorTy()) {
            switch(kind) {
                case T_and:
                    return emitLazyLogical(t,ao,bo,true);
                case T_or:
                    return emitLazyLogical(t,ao,bo,false);
                default:
                    break;
            }
        }
        
        //ok, we have eager operators, lets evalute the arguments then emit
        Value * a = emitExp(ao);
        Value * b = emitExp(bo);

        Obj aot;
        ao->obj("type",&aot);
        TType * at = getType(&aot);
        TType * bt = typeOfValue(bo);
        //CC.EnsureTypeIsComplete(at) (not needed because typeOfValue(ao) ensure the type is complete)
        
        //check for pointer arithmetic first pointer arithmetic first
        if(at->type->isPointerTy() && (kind == T_add || kind == T_sub)) {
            Ty.EnsurePointsToCompleteType(&aot);
            if(bt->type->isPointerTy()) {
                return emitPointerSub(t,a,b);
            } else {
                assert(bt->type->isIntegerTy());
                return emitPointerArith(kind, a, bt, b);
            }
        }
        
        Type * baseT = getPrimitiveType(t);
        
#define RETURN_OP(op) \
if(baseT->isIntegerTy()) { \
    return B->Create##op(a,b); \
} else { \
    return B->CreateF##op(a,b); \
}
#define RETURN_SOP(op) \
if(baseT->isIntegerTy()) { \
    if(t->issigned) { \
        return B->CreateS##op(a,b); \
    } else { \
        return B->CreateU##op(a,b); \
    } \
} else { \
    return B->CreateF##op(a,b); \
}
        switch(kind) {
            case T_add: RETURN_OP(Add) break;
            case T_sub: RETURN_OP(Sub) break;
            case T_mul: RETURN_OP(Mul) break;
            case T_div: RETURN_SOP(Div) break;
            case T_mod: RETURN_SOP(Rem) break;
            case T_pow: return B->CreateXor(a, b);
            case T_and: return B->CreateAnd(a,b);
            case T_or: return B->CreateOr(a,b);
            case T_ne: case T_eq: case T_lt: case T_gt: case T_ge: case T_le: {
                Value * v = emitCompare(exp->kind("operator"),typeOfValue(ao),a,b);
                return B->CreateZExt(v, t->type);
            } break;
            case T_lshift:
                return B->CreateShl(a, b);
                break;
            case T_rshift:
                if(at->issigned)
                    return B->CreateAShr(a, b);
                else
                    return B->CreateLShr(a, b);
                break;
            default:
                assert(!"NYI - binary");
                break;
        }
#undef RETURN_OP
#undef RETURN_SOP
    }
    Value * emitStructCast(Obj * exp, TType * from, Obj * toObj, TType * to, Value * input) {
        //allocate memory to hold input variable
        Obj structvariable;
        exp->obj("structvariable", &structvariable);
        Value * sv = allocVar(&structvariable);
        B->CreateStore(input,sv);
        
        //allocate temporary to hold output variable
        //type must be complete before we try to allocate space for it
        //this is enforced by the callers
        assert(!to->incomplete);
        Value * output = CreateAlloca(B,to->type);
        
        Obj entries;
        exp->obj("entries",&entries);
        int N = entries.size();
        
        for(int i = 0; i < N; i++) {
            Obj entry;
            entries.objAt(i,&entry);
            Obj value;
            entry.obj("value", &value);
            int idx = entry.number("index");
            Value * oe = emitStructSelect(toObj,output,idx);
            Value * in = emitExp(&value); //these expressions will select from the structvariable and perform any casts necessary
            B->CreateStore(in,oe);
        }
        return B->CreateLoad(output);
    }
    Value * emitArrayToPointer(Obj * exp) {
        Value * v = emitAddressOf(exp);
        return B->CreateConstGEP2_32(v,0,0);
    }
    Type * getPrimitiveType(TType * t) {
        if(t->type->isVectorTy())
            return cast<VectorType>(t->type)->getElementType();
        else
            return t->type;
    }
    Value * emitPrimitiveCast(TType * from, TType * to, Value * exp) {
        
        Type * fBase = getPrimitiveType(from);
        Type * tBase = getPrimitiveType(to);
        
        int fsize = fBase->getPrimitiveSizeInBits();
        int tsize = tBase->getPrimitiveSizeInBits();
         
        if(fBase->isIntegerTy()) {
            if(tBase->isIntegerTy()) {
                return B->CreateIntCast(exp, to->type, from->issigned);
            } else if(tBase->isFloatingPointTy()) {
                if(from->issigned) {
                    return B->CreateSIToFP(exp, to->type);
                } else {
                    return B->CreateUIToFP(exp, to->type);
                }
            } else goto nyi;
        } else if(fBase->isFloatingPointTy()) {
            if(tBase->isIntegerTy()) {
                if(to->issigned) {
                    return B->CreateFPToSI(exp, to->type);
                } else {
                    return B->CreateFPToUI(exp, to->type);
                }
            } else if(tBase->isFloatingPointTy()) {
                if(fsize < tsize) {
                    return B->CreateFPExt(exp, to->type);
                } else {
                    return B->CreateFPTrunc(exp, to->type);
                }
            } else goto nyi;
        } else goto nyi;
    nyi:
        assert(!"NYI - casts");
        return NULL;
        
    }
    Value * emitBroadcast(TType * fromT, TType * toT, Value * v) {
        Value * result = UndefValue::get(toT->type);
        VectorType * vt = cast<VectorType>(toT->type);
        Type * integerType = Type::getInt32Ty(*C->ctx);
        for(size_t i = 0; i < vt->getNumElements(); i++)
            result = B->CreateInsertElement(result, v, ConstantInt::get(integerType, i));
        return result;
    }
    bool isPointerToFunction(Type * t) {
        return t->isPointerTy() && t->getPointerElementType()->isFunctionTy();
    }
    Value * emitStructSelect(Obj * structType, Value * structPtr, int index) {

        assert(structPtr->getType()->isPointerTy());
        PointerType * objTy = cast<PointerType>(structPtr->getType());
        assert(objTy->getElementType()->isStructTy());
        Ty.EnsureTypeIsComplete(structType);
        
        Obj layout;
        GetStructEntries(structType,&layout);
        
        Obj entry;
        layout.objAt(index,&entry);
        
        int allocindex = entry.number("allocation");
        
        Value * addr = B->CreateConstGEP2_32(structPtr,0,allocindex);
        //in three cases the type of the value in the struct does not match the expected type returned
        //1. if it is a union then the llvm struct will have some buffer space to hold the object but
        //   the space may have a different type
        //2. if the struct was imported from Clang and the value is a function pointer (Terra internal represents functions with i8* for simplicity)
        //3. if the field was an anonymous C struct, so we don't know its name
        //in all cases we simply bitcast cast the resulting pointer to the expected type
        Obj entryType;
        entry.obj("type",&entryType);
        if (entry.boolean("inunion") || isPointerToFunction(addr->getType()->getPointerElementType())) {
            Type * resultType = PointerType::getUnqual(getType(&entryType)->type);
            addr = B->CreateBitCast(addr, resultType);
        }
        
        return addr;
    }
    Value * emitIfElse(Obj * cond, Obj * a, Obj * b) {
        Value * condExp = emitExp(cond);
        Value * aExp = emitExp(a);
        Value * bExp = emitExp(b);
        condExp = emitCond(condExp); //convert to i1
        return B->CreateSelect(condExp, aExp, bExp);
    }
    Value * variableFromDefinition(Obj * exp) {
        Obj def;
        exp->obj("definition",&def);
        if(def.hasfield("isglobal")) {
            return GetGlobalVariable(T,&def,exp->asstring("name"));
        } else {
            Value * v = (Value*) def.ud("value");
            assert(v);
            return v;
        }
    }
    Value * emitExp(Obj * exp, bool loadlvalue = true) {
        Value * raw = emitExpRaw(exp);
        if(loadlvalue && exp->boolean("lvalue")) {
            Obj type;
            exp->obj("type",&type);
            Ty.EnsureTypeIsComplete(&type);
            raw = B->CreateLoad(raw);
        }
        return raw;
    }
    /* alignment for load

    */
    
    Value * emitExpRaw(Obj * exp) {
        setDebugPoint(exp);
        switch(exp->kind("kind")) {
            case T_var:  {
                return variableFromDefinition(exp);
            } break;
            case T_allocvar: {
                return allocVar(exp);
            } break;
            case T_treelist: {
                return emitTreeList(exp);
            } break;
            case T_operator: {
                
                Obj exps;
                exp->obj("operands",&exps);
                int N = exps.size();
                if(N == 1) {
                    Obj a;
                    exps.objAt(0,&a);
                    return emitUnary(exp,&a);
                } else if(N == 2) {
                    Obj a,b;
                    exps.objAt(0,&a);
                    exps.objAt(1,&b);
                    return emitBinary(exp,&a,&b);
                } else {
                    T_Kind op = exp->kind("operator");
                    if(op == T_select) {
                        Obj a,b,c;
                        exps.objAt(0,&a);
                        exps.objAt(1,&b);
                        exps.objAt(2,&c);
                        return emitIfElse(&a,&b,&c);
                    }
                    exp->dump();
                    assert(!"NYI - unimplemented operator?");
                    return NULL;
                }
                switch(exp->kind("operator")) {
                    case T_add: {
                        TType * t = typeOfValue(exp);
                        Obj exps;
                        
                        if(t->type->isFPOrFPVectorTy()) {
                            Obj a,b;
                            exps.objAt(0,&a);
                            exps.objAt(1,&b);
                            return B->CreateFAdd(emitExp(&a),emitExp(&b));
                        } else {
                            assert(!"NYI - integer +");
                        }
                    } break;
                    default: {
                        assert(!"NYI - op");
                    } break;
                }
                
            } break;
            case T_index: {
                Obj value;
                Obj idx;
                exp->obj("value",&value);
                exp->obj("index",&idx);
                
                Obj aggTypeO;
                value.obj("type",&aggTypeO);
                TType * aggType = getType(&aggTypeO);
                Value * valueExp = emitExp(&value);
                Value * idxExp = emitExp(&idx); 
                
                //if this is a vector index, emit an extractElement
                if(aggType->type->isVectorTy()) {
                    idxExp = emitIndex(typeOfValue(&idx),32,idxExp);
                    Value * result = B->CreateExtractElement(valueExp, idxExp);
                    return result;
                } else {
                    idxExp = emitIndex(typeOfValue(&idx),64,idxExp);
                    //otherwise we have a pointer access which will use a GEP instruction
                    std::vector<Value*> idxs;
                    Ty.EnsurePointsToCompleteType(&aggTypeO);
                    Value * result = B->CreateGEP(valueExp, idxExp);
                    if(!exp->boolean("lvalue"))
                        result = B->CreateLoad(result);
                    return result;
                }
            } break;
            case T_literal: {
                Obj type;
                exp->obj("type", &type);
                TType * t = getType(&type);
                if(t->islogical) {
                   bool b = exp->boolean("value");
                   return ConstantInt::get(t->type,b);
                } else if(t->type->isIntegerTy()) {
                    uint64_t integer = exp->integer("value");
                    return ConstantInt::get(t->type, integer);
                } else if(t->type->isFloatingPointTy()) {
                    double dbl = exp->number("value");
                    return ConstantFP::get(t->type, dbl);
                } else if(t->type->isPointerTy()) {
                    PointerType * pt = cast<PointerType>(t->type);
                    if(type.kind("kind") == T_niltype) {
                        return ConstantPointerNull::get(pt);
                    }
                    
                    Obj objType;
                    type.obj("type",&objType);
                    if(objType.kind("kind") == T_functype) {
                        Obj func;
                        exp->obj("value",&func);
                        Function * fn;
                        getOrCreateFunction(&func,&fn);
                        //functions are represented with &int8 pointers to avoid
                        //calling convension issues, so cast the literal to this type now
                        return B->CreateBitCast(fn,t->type);
                    } else if(t->type->getPointerElementType()->isIntegerTy(8)) {
                        exp->pushfield("value");
                        size_t len;
                        const char * rawstr = lua_tolstring(L,-1,&len);
                        Value * str = B->CreateGlobalString(StringRef(rawstr,len),"$string"); //needs a name to make mcjit work in 3.5
                        lua_pop(L,1);
                        return  B->CreateBitCast(str, pt);
                    } else {
                        assert(!"NYI - pointer literal");
                    }
                } else {
                    exp->dump();
                    assert(!"NYI - literal");
                }
            } break;
            case T_constant: {
                Obj value;
                exp->obj("value",&value);
                return GetConstant(T,&value);
            } break;
            case T_luafunction: {
                void * ptr = exp->ud("fptr");
                Constant * ptrint = ConstantInt::get(C->td->getIntPtrType(*C->ctx), (intptr_t)ptr);
                return ConstantExpr::getIntToPtr(ptrint, typeOfValue(exp)->type);
            } break;
            case T_apply: {
                return emitCall(exp,false);
            } break;
            case T_cast: {
                Obj a;
                Obj to,from;
                exp->obj("expression",&a);
                exp->obj("to",&to);
                exp->obj("from",&from);
                TType * fromT = getType(&from);
                TType * toT = getType(&to);
                if(fromT->type->isArrayTy()) {
                    return emitArrayToPointer(&a);
                }
                Value * v = emitExp(&a);
                if(fromT->type->isStructTy()) {
                    return emitStructCast(exp,fromT,&to,toT,v);
                } else if(fromT->type->isPointerTy()) {
                    if(toT->type->isPointerTy()) {
                        return B->CreateBitCast(v, toT->type);
                    } else {
                        assert(toT->type->isIntegerTy());
                        return B->CreatePtrToInt(v, toT->type);
                    }
                } else if(toT->type->isPointerTy()) {
                    assert(fromT->type->isIntegerTy());
                    return B->CreateIntToPtr(v, toT->type);
                } else if(toT->type->isVectorTy()) {
                    if(fromT->type->isVectorTy())
                        return emitPrimitiveCast(fromT,toT,v);
                    else
                        return emitBroadcast(fromT, toT, v);
                } else {
                    return emitPrimitiveCast(fromT,toT,v);
                }
            } break;
            case T_sizeof: {
                Obj typ;
                exp->obj("oftype",&typ);
                TType * tt = getType(&typ);
                return ConstantInt::get(Type::getInt64Ty(*C->ctx),C->td->getTypeAllocSize(tt->type));
            } break;   
            case T_select: {
                Obj obj,typ;
                exp->obj("value",&obj);
                /*TType * vt =*/typeOfValue(&obj);
                
                obj.obj("type",&typ);
                int offset = exp->number("index");
                
                Value * v = emitAddressOf(&obj);
                Value * result = emitStructSelect(&typ,v,offset);
                if(!exp->boolean("lvalue"))
                   result = B->CreateLoad(result);
                return result;
            } break;
            case T_constructor: case T_arrayconstructor: {
                Obj expressions;
                exp->obj("expressions",&expressions);
                return emitConstructor(exp,&expressions);
            } break;
            case T_vectorconstructor: {
                Obj expressions;
                exp->obj("expressions",&expressions);
                std::vector<Value *> values;
                emitExpressionList(&expressions,true,&values);
                TType * vecType = typeOfValue(exp);
                Value * vec = UndefValue::get(vecType->type);
                Type * intType = Type::getInt32Ty(*C->ctx);
                for(size_t i = 0; i < values.size(); i++) {
                    vec = B->CreateInsertElement(vec, values[i], ConstantInt::get(intType, i));
                }
                return vec;
            } break;
            case T_inlineasm: {
                Obj arguments;
                exp->obj("arguments",&arguments);
                std::vector<Value *> values;
                emitExpressionList(&arguments,true,&values);
                Obj typ;
                exp->obj("type",&typ);
                bool isvoid = Ty.IsUnitType(&typ);
                Type * ttype = getType(&typ)->type;
                Type * rtype = (isvoid) ? Type::getVoidTy(*C->ctx) : ttype;
                std::vector<Type*> ptypes;
                for(size_t i = 0; i < values.size(); i++)
                    ptypes.push_back(values[i]->getType());
                Value * fn = InlineAsm::get(FunctionType::get(rtype, ptypes, false),exp->string("asm"),exp->string("constraints"),exp->boolean("volatile"));
                Value * call = B->CreateCall(fn,values);
                return (isvoid) ? UndefValue::get(ttype) : call;
            } break;
            case T_attrload: {
                Obj addr,type,attr;
                exp->obj("type",&type);
                exp->obj("address",&addr);
                exp->obj("attributes",&attr);
                Ty.EnsureTypeIsComplete(&type);
                LoadInst * l = B->CreateLoad(emitExp(&addr));
                if(attr.hasfield("alignment")) {
                    int alignment = attr.number("alignment");
                    l->setAlignment(alignment);
                }
                if(attr.hasfield("isvolatile")) {
                  bool isVolatile = attr.boolean("isvolatile");
                  l->setVolatile(isVolatile);
                }
                return l;
            } break;
            case T_attrstore: {
                Obj addr,attr,value;
                exp->obj("address",&addr);
                exp->obj("attributes",&attr);
                exp->obj("value",&value);
                Value * addrexp = emitExp(&addr);
                Value * valueexp = emitExp(&value);
                StoreInst * store = B->CreateStore(valueexp,addrexp);
                if(attr.hasfield("alignment")) {
                    int alignment = attr.number("alignment");
                    store->setAlignment(alignment);
                }
                if(attr.hasfield("nontemporal")) {
                    store->setMetadata("nontemporal", MDNode::get(*C->ctx, ConstantInt::get(Type::getInt32Ty(*C->ctx), 1)));
                }
                if(attr.hasfield("isvolatile")) {
                  bool isVolatile = attr.boolean("isvolatile");
                  store->setVolatile(isVolatile);
                }
                return Constant::getNullValue(typeOfValue(exp)->type);
            } break;
            case T_debuginfo: {
                customfilename = exp->string("customfilename");
                customlinenumber = exp->number("customlinenumber");
                return Constant::getNullValue(typeOfValue(exp)->type);
            } break;
            default: {
                exp->dump();
                assert(!"NYI - exp");
            } break;
        }
    }
    BasicBlock * createAndInsertBB(StringRef name) {
        return BasicBlock::Create(*C->ctx, name,func);
    }
    void followsBB(BasicBlock * b) {
        b->moveAfter(B->GetInsertBlock());
    }
    Value * emitCond(Obj * cond) {
        return emitCond(emitExp(cond));
    }
    Value * emitCond(Value * cond) {
        Type * resultType = Type::getInt1Ty(*C->ctx);
        if(cond->getType()->isVectorTy()) {
            VectorType * vt = cast<VectorType>(cond->getType());
            resultType = VectorType::get(resultType,vt->getNumElements());
        }
        return B->CreateTrunc(cond, resultType);
    }
    void emitIfBranch(Obj * ifbranch, BasicBlock * footer) {
        Obj cond,body;
        ifbranch->obj("condition", &cond);
        ifbranch->obj("body",&body);
        BasicBlock * thenBB = createAndInsertBB("then");
        BasicBlock * continueif = createAndInsertBB("else");
        emitBranchOnExpr(&cond, thenBB, continueif);
        
        setInsertBlock(thenBB);
        
        emitStmt(&body);
        B->CreateBr(footer);
        followsBB(continueif);
        setInsertBlock(continueif);
        
    }
    
    DIFile createDebugInfoForFile(const char * filename) {
        //checking the existence of a file once per function can be expensive,
        //so only do it if debug mode is set to slow compile anyway.
        //In the future, we can cache across functions calls if needed
        if(T->options.debug > 1 && llvm::sys::fs::exists(filename)) {
            SmallString<256> filepath = StringRef(filename);
            llvm::sys::fs::make_absolute(filepath);
            return DB->createFile(llvm::sys::path::filename(filepath),llvm::sys::path::parent_path(filepath));
        } else {
            return DB->createFile(filename,".");
        }
    }
    MDNode * debugScopeForFile(const char * filename) {
        StringMap<MDNode*>::iterator it = filenamecache.find(filename);
        if(it != filenamecache.end())
            return it->second;
        MDNode * block = DB->createLexicalBlockFile(SP, createDebugInfoForFile(filename));
        filenamecache[filename] = block;
        return block;
    }
    void initDebug(const char * filename, int lineno) {
        customfilename = NULL;
        customlinenumber = 0;
        DEBUG_ONLY(T) {
            DB = new DIBuilder(*C->m);
            
            DIFile file = createDebugInfoForFile(filename);
            #if LLVM_VERSION >= 34
            DICompileUnit CU =
            #endif
                DB->createCompileUnit(1, "compilationunit", ".", "terra", true, "", 0);
            SP = DB->createFunction(
                                    #if LLVM_VERSION >= 34
                                    CU,
                                    #else
                                    (DIDescriptor)DB->getCU(),
                                    #endif
                                    func->getName(), func->getName(), file, lineno,
                                    DB->createSubroutineType(file, DB->getOrCreateArray(ArrayRef<Value*>())),
                                    false, true, 0,0, true, func);
            
            if(!T->C->m->getModuleFlagsMetadata()) {
                T->C->m->addModuleFlag(llvm::Module::Warning, "Dwarf Version",2);
                T->C->m->addModuleFlag(llvm::Module::Warning, "Debug Info Version",1);
            }
            filenamecache[filename] = SP;
        }
    }
    void endDebug() {
        DEBUG_ONLY(T) {
            DB->finalize();
            delete DB;
        }
    }
    void setDebugPoint(Obj * obj) {
        DEBUG_ONLY(T) {
            MDNode * scope = debugScopeForFile(customfilename ? customfilename : obj->string("filename"));
            B->SetCurrentDebugLocation(DebugLoc::get(customfilename ? customlinenumber : obj->number("linenumber"), 0, scope));
        }
    }
    void setInsertBlock(BasicBlock * bb) {
        B->SetInsertPoint(bb);
    }
    void setBreaktable(Obj * loop, BasicBlock * exit) {
        //set the break table for this loop to point to the loop exit
        Obj breaktable;
        loop->obj("breaktable",&breaktable);
        
        lua_pushlightuserdata(L, exit);
        breaktable.setfield("value");
    }
    BasicBlock * getOrCreateBlockForLabel(Obj * lbl) {
        BasicBlock * bb = (BasicBlock *) lbl->ud("basicblock");
        if(!bb) {
            bb = createAndInsertBB(lbl->string("labelname"));
            lua_pushlightuserdata(L,bb);
            lbl->setfield("basicblock");
        }
        return bb;
    }
    Value * emitCall(Obj * call, bool defer) {
        Obj paramlist;
        Obj paramtypes;
        Obj func;
        
        call->obj("arguments",&paramlist);
        call->obj("paramtypes",&paramtypes);
        call->obj("value",&func);
        
        Value * fn = emitExp(&func);
        
        Obj fnptrtyp;
        func.obj("type",&fnptrtyp);
        Obj fntyp;
        fnptrtyp.obj("type",&fntyp);
        
        std::vector<Value*> actuals;
        emitExpressionList(&paramlist,true,&actuals);
        BasicBlock * cur = B->GetInsertBlock();
        if(defer) {
            BasicBlock * bb = createAndInsertBB("defer");
            setInsertBlock(bb);
            deferred.push_back(bb);
        }
        Value * r = CC.EmitCall(&fntyp,&paramtypes, fn, &actuals);
        setInsertBlock(cur); //defer may have changed it
        return r;
    }
    
    void emitReturnUndef() {
        Type * rt = func->getReturnType();
        if(rt->isVoidTy()) {
            B->CreateRetVoid();
        } else {
            B->CreateRet(UndefValue::get(rt));
        }
    }
    void emitExpressionList(Obj * exps, bool loadlvalue, std::vector<Value*> * results) {
        int N = exps->size();
        for(int i = 0; i < N; i++) {
            Obj exp;
            exps->objAt(i, &exp);
            results->push_back(emitExp(&exp,loadlvalue));
        }
    }
    Value * emitConstructor(Obj * exp, Obj * expressions) {
        Value * result = CreateAlloca(B,typeOfValue(exp)->type);
        std::vector<Value *> values;
        emitExpressionList(expressions,true,&values);
        for(size_t i = 0; i < values.size(); i++) {
            Value * addr = B->CreateConstGEP2_32(result,0,i);
            B->CreateStore(values[i],addr);
        }
        return B->CreateLoad(result);
    }
    Value * emitTreeList(Obj * treelist) {
        Obj stmts;
        if(treelist->obj("statements",&stmts)) {
            int NS = stmts.size();
            for(int i = 0; i < NS; i++) {
                Obj s;
                stmts.objAt(i,&s);
                emitStmt(&s);
            }
        }
        Obj exps;
        if(!treelist->obj("expressions",&exps))
            return NULL;
        if (exps.size() == 1) {
            Obj exp;
            exps.objAt(0,&exp);
            return emitExp(&exp,false);
        }
        return emitConstructor(treelist, &exps);
    }
    void startDeadCode() {
        BasicBlock * bb = createAndInsertBB("dead");
        setInsertBlock(bb);
    }
    //emit an exit path that includes the most recent num deferred statements
    //this is used by gotos,returns, and breaks. unlike scope ends it copies the dtor stack
    void emitDeferred(size_t num) {
        ValueToValueMapTy VMap;
        for(size_t i = 0; i < num; i++) {
            BasicBlock * bb = deferred[deferred.size() - 1 - i];
            bb = CloneBasicBlock(bb, VMap, "", func);
            B->CreateBr(bb);
            setInsertBlock(bb);
        }
    }
    //unwind deferred and remove them from dtor stack, no need to copy the BB, since this is its last use
    void unwindDeferred(size_t to) {
        for(; deferred.size() > to; deferred.pop_back()) {
            BasicBlock * bb = deferred.back();
            B->CreateBr(bb);
            setInsertBlock(bb);
        }
    }
    void emitStmt(Obj * stmt) {
        setDebugPoint(stmt);
        T_Kind kind = stmt->kind("kind");
        switch(kind) {
            case T_block: {
                size_t N = deferred.size();
                Obj treelist;
                stmt->obj("body",&treelist);
                emitStmt(&treelist);
                unwindDeferred(N);
            } break;
            case T_return: {
                Obj exp;
                stmt->obj("expression",&exp);
                Value * result = emitExp(&exp);;
                Obj ftype;
                funcobj->obj("type",&ftype);
                emitDeferred(deferred.size());
                CC.EmitReturn(&ftype,func,result);
                startDeadCode();
            } break;
            case T_label: {
                BasicBlock * bb = getOrCreateBlockForLabel(stmt);
                B->CreateBr(bb);
                followsBB(bb);
                setInsertBlock(bb);
            } break;
            case T_goto: {
                Obj lbl;
                stmt->obj("definition",&lbl);
                BasicBlock * bb = getOrCreateBlockForLabel(&lbl);
                emitDeferred(stmt->number("deferred"));
                B->CreateBr(bb);
                startDeadCode();
            } break;
            case T_break: {
                Obj def;
                stmt->obj("breaktable",&def);
                BasicBlock * breakpoint = (BasicBlock *) def.ud("value");
                assert(breakpoint);
                emitDeferred(stmt->number("deferred"));
                B->CreateBr(breakpoint);
                startDeadCode();
            } break;
            case T_while: {
                Obj cond,body;
                stmt->obj("condition",&cond);
                stmt->obj("body",&body);
                BasicBlock * condBB = createAndInsertBB("condition");
                
                B->CreateBr(condBB);
                
                setInsertBlock(condBB);
                
                BasicBlock * loopBody = createAndInsertBB("whilebody");
    
                BasicBlock * merge = createAndInsertBB("merge");
                
                setBreaktable(stmt,merge);
                
                emitBranchOnExpr(&cond, loopBody, merge);
                
                setInsertBlock(loopBody);
                
                emitStmt(&body);
                
                B->CreateBr(condBB);
                
                followsBB(merge);
                setInsertBlock(merge);
            } break;
            case T_fornum: {
                Obj initial,step,limit,variable,body;
                stmt->obj("initial",&initial);
                bool hasstep = stmt->obj("step",&step);
                stmt->obj("limit",&limit);
                stmt->obj("variable",&variable);
                stmt->obj("body",&body);
                TType * t = typeOfValue(&variable);
                Value * initialv = emitExp(&initial);
                Value * limitv = emitExp(&limit);
                Value * stepv = (hasstep) ? emitExp(&step) : ConstantInt::get(t->type,1);
                Value * vp = emitExp(&variable,false);
                Value * zero = ConstantInt::get(t->type,0);
                B->CreateStore(initialv, vp);
                BasicBlock * cond = createAndInsertBB("forcond");
                B->CreateBr(cond);
                setInsertBlock(cond);
                Value * v = B->CreateLoad(vp);
                Value * c = B->CreateOr(B->CreateAnd(emitCompare(T_lt,t, v, limitv), emitCompare(T_gt,t,stepv,zero)),
                                        B->CreateAnd(emitCompare(T_gt,t, v, limitv), emitCompare(T_le,t,stepv,zero)));
                BasicBlock * loopBody = createAndInsertBB("forbody");
                BasicBlock * merge = createAndInsertBB("merge");
                setBreaktable(stmt,merge);
                B->CreateCondBr(c,loopBody,merge);
                setInsertBlock(loopBody);
                emitStmt(&body);
                B->CreateStore(B->CreateAdd(v, stepv),vp);
                B->CreateBr(cond);
                followsBB(merge);
                setInsertBlock(merge);
            } break;
            case T_if: {
                Obj branches;
                stmt->obj("branches",&branches);
                int N = branches.size();
                BasicBlock * footer = createAndInsertBB("merge");
                for(int i = 0; i < N; i++) {
                    Obj branch;
                    branches.objAt(i,&branch);
                    emitIfBranch(&branch,footer);
                }
                Obj orelse;
                if(stmt->obj("orelse",&orelse))
                    emitStmt(&orelse);
                B->CreateBr(footer);
                followsBB(footer);
                setInsertBlock(footer);
            } break;
            case T_repeat: {
                Obj cond,body;
                stmt->obj("condition",&cond);
                stmt->obj("body",&body);
                
                BasicBlock * loopBody = createAndInsertBB("repeatbody");
                BasicBlock * merge = createAndInsertBB("merge");
                
                setBreaktable(stmt,merge);
                
                B->CreateBr(loopBody);
                setInsertBlock(loopBody);
                size_t N = deferred.size();
                emitStmt(&body);
                if(N < deferred.size()) { //because the body and the conditional are in the same block scope
                                          //we need special handling for deferred
                                          //along the back edge of the loop we must emit the deferred blocks
                    BasicBlock * backedge = createAndInsertBB("repeatdeferred");
                    setInsertBlock(backedge);
                    emitDeferred(deferred.size() - N);
                    B->CreateBr(loopBody);
                    setInsertBlock(loopBody);
                    loopBody = backedge;
                }
                emitBranchOnExpr(&cond, merge, loopBody);
                
                followsBB(merge);
                setInsertBlock(merge);
                unwindDeferred(N);
            } break;
            case T_assignment: {
                std::vector<Value *> rhsexps;
                Obj rhss;
                stmt->obj("rhs",&rhss);
                emitExpressionList(&rhss,true,&rhsexps);
                Obj lhss;
                stmt->obj("lhs",&lhss);
                int N = lhss.size();
                for(int i = 0; i < N; i++) {
                    Obj lhs;
                    lhss.objAt(i,&lhs);
                    if(lhs.kind("kind") == T_setter) {
                        Obj rhsvar,setter;
                        lhs.obj("rhs",&rhsvar);
                        lhs.obj("setter",&setter);
                        Value * rhsvarV = emitExp(&rhsvar,false);
                        B->CreateStore(rhsexps[i],rhsvarV);
                        emitExp(&setter);
                    } else {
                        B->CreateStore(rhsexps[i],emitExp(&lhs,false));
                    }
                }
            } break;
            case T_defer: {
                Obj expression;
                stmt->obj("expression",&expression);
                emitCall(&expression, true);
            } break;
            default: {
                emitExp(stmt,false);
            } break;
        }
    }
};

static int terra_codegen(lua_State * L) { //entry point into compiler from lua code
    terra_State * T = terra_getstate(L, 1);
    
    //create lua table to hold object references anchored on stack
    int ref_table = lobj_newreftable(T->L);
    
    {
        lua_pushvalue(T->L,-2); //the original argument
        Obj funcobj;
        funcobj.initFromStack(T->L, ref_table);
        
        TerraCompiler(T,&funcobj);
        
        //cleanup -- ensure we left the stack the way we started
        assert(lua_gettop(T->L) == ref_table);
        
    } //scope to ensure that all Obj held in the compiler are destroyed before we pop the reference table off the stack
    
    lobj_removereftable(T->L,ref_table);
    
    return 0;
}

static int terra_llvmsizeof(lua_State * L) {
    terra_State * T = terra_getstate(L, 1);
    int ref_table = lobj_newreftable(L);
    TType * llvmtyp;
    {
        lua_pushvalue(T->L,-2); //original argument
        Obj typ;
        typ.initFromStack(L, ref_table);
        llvmtyp = Types(T).Get(&typ);
    }
    lobj_removereftable(T->L, ref_table);
    lua_pushnumber(T->L,T->C->td->getTypeAllocSize(llvmtyp->type));
    return 1;
}

static int terra_optimize(lua_State * L) {
    terra_State * T = terra_getstate(L, 1);
    
    int ref_table = lobj_newreftable(T->L);
    
    {
        Obj jitobj;
        lua_pushvalue(L,-2); //original argument
        jitobj.initFromStack(L, ref_table);
        Obj funclist;
        Obj flags;
        jitobj.obj("functions", &funclist);
        jitobj.obj("flags",&flags);
        std::vector<Function *> scc;
        int N = funclist.size();
        VERBOSE_ONLY(T) {
            printf("optimizing scc containing: ");
        }
        for(int i = 0; i < N; i++) {
            Obj funcobj;
            funclist.objAt(i,&funcobj);
            Function * func = (Function*) funcobj.ud("llvm_value");
            assert(func);
            scc.push_back(func);
            VERBOSE_ONLY(T) {
                std::string s = func->getName();
                printf("%s ",s.c_str());
            }
        }
        VERBOSE_ONLY(T) {
            printf("\n");
        }
        
        T->C->mi->run(&scc);
    
        for(int i = 0; i < N; i++) {
            Obj funcobj;
            funclist.objAt(i,&funcobj);
            Function * func = (Function*) funcobj.ud("llvm_value");
            assert(func);
            
            VERBOSE_ONLY(T) {
                std::string s = func->getName();
                printf("optimizing %s\n",s.c_str());
            }
            double begin = CurrentTimeInSeconds();
            T->C->fpm->run(*func);
            RecordTime(&funcobj,"opt",begin);
            
            VERBOSE_ONLY(T) {
                func->dump();
            }
        }
    } //scope to ensure that all Obj held in the compiler are destroyed before we pop the reference table off the stack
    
    lobj_removereftable(T->L,ref_table);
    
    return 0;
}



#ifdef TERRA_CAN_USE_MCJIT
static void * GetGlobalValueAddress(terra_State * T, StringRef Name) {
    if(T->options.debug > 1)
        return sys::DynamicLibrary::SearchForAddressOfSymbol(Name);
    return (void*)T->C->ee->getGlobalValueAddress(Name);
}
static bool MCJITShouldCopy(GlobalValue * G, void * data) {
    terra_State * T = (terra_State*) data;
    if(dyn_cast<Function>(G) != NULL || dyn_cast<GlobalVariable>(G) != NULL)
        return 0 == GetGlobalValueAddress(T,G->getName());
    return true;
}
#endif

static bool SaveSharedObject(terra_State * T, Module * M, std::vector<const char *> * args, const char * filename);

static void * JITGlobalValue(terra_State * T, GlobalValue * gv) {
    ExecutionEngine * ee = T->C->ee;
    if (T->options.usemcjit) {
#ifdef TERRA_CAN_USE_MCJIT
        if(gv->isDeclaration()) {
            return ee->getPointerToNamedFunction(gv->getName());
        }
        void * ptr =  GetGlobalValueAddress(T,gv->getName());
        if(ptr) {
            return ptr;
        }
        llvm::ValueToValueMapTy VMap;
        Module * m = llvmutil_extractmodulewithproperties(gv->getName(), gv->getParent(), &gv, 1, MCJITShouldCopy,T, VMap);
        
        if(T->options.debug > 1) {
            llvm::SmallString<256> tmpname;
            llvmutil_createtemporaryfile("terra","so",tmpname);
            if(SaveSharedObject(T, m, NULL, tmpname.c_str()))
                lua_error(T->L);
            sys::DynamicLibrary::LoadLibraryPermanently(tmpname.c_str());
            void * result = sys::DynamicLibrary::SearchForAddressOfSymbol(gv->getName());
            assert(result);
            return result;
        }
        ee->addModule(m);
        return (void*) ee->getGlobalValueAddress(gv->getName());
#else
        return NULL;
#endif
    } else {
        return ee->getPointerToGlobal(gv);
    }
}

static int terra_jit(lua_State * L) {
    terra_State * T = terra_getstate(L, 1);
    
    int ref_table = lobj_newreftable(T->L);
    
    {
        Obj jitobj, funcobj, flags;
        lua_pushvalue(L,-2); //original argument
        jitobj.initFromStack(L, ref_table);
        jitobj.obj("func", &funcobj);
        jitobj.obj("flags",&flags);
        Function * func = (Function*) funcobj.ud("llvm_value");
        assert(func);
        
        double begin = CurrentTimeInSeconds();
        void * ptr = JITGlobalValue(T,func);
        RecordTime(&funcobj,"gen",begin);
        
        lua_pushlightuserdata(L, ptr);
        funcobj.setfield("llvm_ptr");
    } //scope to ensure that all Obj held in the compiler are destroyed before we pop the reference table off the stack
    
    lobj_removereftable(T->L,ref_table);
    
    return 0;
}

static int terra_createglobal(lua_State * L) { //entry point into compiler from lua code
    terra_State * T = terra_getstate(L, 1);
    
    //create lua table to hold object references anchored on stack
    int ref_table = lobj_newreftable(T->L);
    
    {
        Obj global;
        lua_pushvalue(T->L,-2); //original argument
        global.initFromStack(T->L, ref_table);
        GlobalVariable * gv = GetGlobalVariable(T,&global,"anon");
        void * ptr = JITGlobalValue(T, gv);
        lua_pushlightuserdata(L,ptr);
        global.setfield("llvm_ptr");
        lua_pushstring(L,gv->getName().data());
        global.setfield("llvm_name");
    } //scope to ensure that all Obj held in the compiler are destroyed before we pop the reference table off the stack
    
    lobj_removereftable(T->L,ref_table);
    
    return 0;
}

static int terra_registerexternfunction(lua_State * L) {
    terra_State * T = terra_getstate(L, 1);
    int ref_table = lobj_newreftable(L);
    {
        Obj fn;
        lua_pushvalue(L, -2);
        fn.initFromStack(L,ref_table);
        const char * name = fn.string("name");
        llvm::Function * llvmfn = T->C->m->getFunction(name);
        if(!llvmfn) { //declared directly from Terra, so the declaration was not linked in by C
            Types Ty(T);
            CCallingConv CC(T,&Ty,NULL);
            Obj typ;
            fn.obj("type",&typ);
            llvmfn = CC.CreateFunction(&typ,name);
        }
        assert(llvmfn);
        lua_pushlightuserdata(L, llvmfn);
        fn.setfield("llvm_value");
    }
    lobj_removereftable(L, ref_table);
    return 0;
}

static int terra_deletefunction(lua_State * L) {
    terra_State * T = terra_getstate(L, 1);
    Function ** fp = (Function**) lua_touserdata(L,-1);
    assert(fp);
    Function * func = (Function*) *fp;
    assert(func);
    VERBOSE_ONLY(T) {
        printf("deleting function: %s\n",func->getName().str().c_str());
    }
    //MCJIT can't free individual functions, so we need to leak the generated code
    if(!T->options.usemcjit && T->C->ee->getPointerToGlobalIfAvailable(func)) {
        VERBOSE_ONLY(T) {
            printf("... and deleting generated code\n");
        }
        T->C->ee->freeMachineCodeForFunction(func); 
    }
    if(!func->use_empty() || T->options.usemcjit) { //for MCJIT, we need to keep the declaration so another function doesn't get the same name
        VERBOSE_ONLY(T) {
            printf("... uses not empty, removing body but keeping declaration.\n");
        }
        func->deleteBody();
    } else {
        T->C->mi->eraseFunction(func);
    }
    VERBOSE_ONLY(T) {
        printf("... finish delete.\n");
    }
    *fp = NULL;
    terra_decrementlivefunctions(T);
    return 0;
}
static int terra_disassemble(lua_State * L) {
    terra_State * T = terra_getstate(L, 1);
    
    lua_getfield(L,-1,"llvm_value");
    Function * fn = (Function*) lua_touserdata(L,-1);
    lua_pop(L,1); //llvm_value
    fn->dump();
    
    lua_getfield(L,-1,"llvm_ptr");
    void * addr = lua_touserdata(L, -1);
    if(T->C->functioninfo.count(addr)) {
        TerraFunctionInfo & fi = T->C->functioninfo[addr];
        printf("assembly for function at address %p\n",addr);
        llvmutil_disassemblefunction(fi.addr, fi.size,0);
    }
    return 0;
}

static bool FindLinker(LLVM_PATH_TYPE * linker) {
#ifndef _WIN32
    #if LLVM_VERSION >= 34
        *linker = sys::FindProgramByName("gcc");
        return *linker == "";
    #else
        *linker = sys::Program::FindProgramByName("gcc");
        return linker->isEmpty();
    #endif
#else
    *linker = LLVM_PATH_TYPE (CLANG_EXECUTABLE);
#endif
    return false;
}

static bool SaveAndLink(terra_State * T, Module * M, std::vector<const char *> * linkargs, const char * filename) {
    llvm::SmallString<256> tmpname;
    llvmutil_createtemporaryfile("terra","o", tmpname);
    const char * tmpnamebuf = tmpname.c_str();
    std::string err;
    raw_fd_ostream tmp(tmpnamebuf,err,RAW_FD_OSTREAM_BINARY);
    if(!err.empty()) {
        terra_pusherror(T,"llvm: %s",err.c_str());
        unlink(tmpnamebuf);
        return true;
    }
    if(llvmutil_emitobjfile(M,T->C->tm,tmp,&err)) {
        terra_pusherror(T,"llvm: %s",err.c_str());
        unlink(tmpnamebuf);
        return true;
    }
    LLVM_PATH_TYPE linker;
    if(FindLinker(&linker)) {
        unlink(tmpnamebuf);
        terra_pusherror(T,"llvm: failed to find linker");
        return true;
    }
    std::vector<const char *> cmd;
    cmd.push_back(linker.c_str());
    cmd.push_back(tmpnamebuf);
    if(linkargs)
        cmd.insert(cmd.end(),linkargs->begin(),linkargs->end());
    
    cmd.push_back("-o");
    cmd.push_back(filename);
    cmd.push_back(NULL);
    
    if(llvmutil_executeandwait(linker,&cmd[0],&err)) {
        unlink(tmpnamebuf);
        unlink(filename);
        terra_pusherror(T,"llvm: %s\n",err.c_str());
        return true;
    }
    return false;
}

static bool SaveObject(terra_State * T, Module * M, const std::string & filekind, raw_ostream & dest) {
    std::string err;
    if(filekind == "object") {
        if(llvmutil_emitobjfile(M,T->C->tm,dest,&err)) {
            terra_pusherror(T,"llvm: %s\n",err.c_str());
            return true;
        }
    } else if(filekind == "bitcode") {
        llvm::WriteBitcodeToFile(M,dest);
    } else if(filekind == "llvmir") {
        dest << *M;
    }
    return false;
}
static bool SaveSharedObject(terra_State * T, Module * M, std::vector<const char *> * args, const char * filename) {
    std::vector<const char *> cmd;
    cmd.push_back("-g");
#ifdef __APPLE__
    cmd.push_back("-dynamiclib");
    cmd.push_back("-single_module");
    cmd.push_back("-undefined");
    cmd.push_back("dynamic_lookup");
#else
    cmd.push_back("-shared");
    cmd.push_back("-Wl,-export-dynamic");
    cmd.push_back("-ldl");
#endif
    cmd.push_back("-fPIC");
    if(args)
        cmd.insert(cmd.end(),args->begin(),args->end());
    return SaveAndLink(T,M,&cmd,filename);
}

static int terra_saveobjimpl(lua_State * L) {
    terra_State * T = terra_getstate(L, 1);
    
    const char * filename = lua_tostring(L, 1); //NULL means write to memory
    std::string filekind = lua_tostring(L,2); 
    int tbl = 3;
    int argument_index = 4;
    
    std::vector<GlobalValue *> livefns;
    std::vector<std::string> names;
    Module * M;
    std::vector<const char *> args;
    
    int ref_table = lobj_newreftable(T->L);
    {
        //iterate over the key value pairs in the table
        lua_pushnil(L);
        while (lua_next(L, tbl) != 0) {
            const char * key = luaL_checkstring(L, -2);
            Obj obj;
            obj.initFromStack(L, ref_table);
            Function * fnold = (Function*) obj.ud("llvm_value");
            assert(fnold);
            names.push_back(key);
            livefns.push_back(fnold);
        }
        
        M = llvmutil_extractmodule(T->C->m, T->C->tm, &livefns, &names, true);
        
        VERBOSE_ONLY(T) {
            printf("extracted module is:\n");
            M->dump();
        }
        
        lua_pushvalue(L,argument_index);
        Obj arguments;
        arguments.initFromStack(L,ref_table);
        
        int N = arguments.size();
        for(int i = 0; i < N; i++) {
            Obj arg;
            arguments.objAt(i,&arg);
            arg.push();
            args.push_back(luaL_checkstring(L,-1));
            lua_pop(L,1);
        }
    }
    lobj_removereftable(T->L, ref_table);
    
    bool result = false;
    int N = 0;
    
    if (filekind == "executable") {
        result = SaveAndLink(T,M,&args,filename);
    } else if (filekind == "sharedlibrary") {
        result = SaveSharedObject(T,M,&args,filename);
    } else  {
        if(filename != NULL) {
            std::string err;
            raw_fd_ostream dest(filename, err, (filekind == "llvmir") ? RAW_FD_OSTREAM_NONE : RAW_FD_OSTREAM_BINARY);
            if (!err.empty()) {
                terra_pusherror(T, "llvm: %s", err.c_str());
                result = true;
            } else {
                result = SaveObject(T,M, filekind, dest);
            }
        } else {
            SmallVector<char,256> mem;
            raw_svector_ostream dest(mem);
            result = SaveObject(T,M,filekind,dest);
            N = 1;
            lua_pushlstring(L,&mem[0],mem.size());
        }
    }
    
    delete M;
    if(result)
        lua_error(T->L);
    
    return N;
}

static int terra_pointertolightuserdata(lua_State * L) {
    //argument is a 'cdata'.
    //calling topointer on it will return a pointer to the cdata payload
    //here we know the payload is a pointer, which we extract:
    void ** cdata = (void**) lua_topointer(L,-1);
    assert(cdata);
    lua_pushlightuserdata(L, *cdata);
    return 1;
}
#ifdef _WIN32
#define ISFINITE(v) _finite(v)
#else
#define ISFINITE(v) std::isfinite(v)
#endif
static int terra_isintegral(lua_State * L) {
    double v = luaL_checknumber(L,-1);
    bool integral = ISFINITE(v) && (double)(int)v == v; 
    lua_pushboolean(L,integral);
    return 1;
}

static int terra_linklibraryimpl(lua_State * L) {
    std::string Err;
    terra_State * T = terra_getstate(L, 1);
    
    const char * filename = luaL_checkstring(L, -2);
    bool isbitcode = lua_toboolean(L,-1);
    if(isbitcode) {
    #if LLVM_VERSION <= 34
        OwningPtr<MemoryBuffer> mb;
        error_code ec = MemoryBuffer::getFile(filename,mb);
        if(ec)
            terra_reporterror(T, "llvm: %s\n", ec.message().c_str());
        Module * m = ParseBitcodeFile(mb.get(), *T->C->ctx,&Err);
        m->setTargetTriple(T->C->m->getTargetTriple());
        if(!m)
            terra_reporterror(T, "llvm: %s\n", Err.c_str());
    #else
        ErrorOr<std::unique_ptr<MemoryBuffer> > mb = MemoryBuffer::getFile(filename);
        if(!mb)
            terra_reporterror(T, "llvm: %s\n", mb.getError().message().c_str());
        ErrorOr<Module *> mm = parseBitcodeFile(mb.get().get(),*T->C->ctx);
        if(!mm)
            terra_reporterror(T, "llvm: %s\n", mm.getError().message().c_str());
        Module * m = mm.get();
    #endif
        m->setTargetTriple(T->C->m->getTargetTriple());
        bool failed = llvmutil_linkmodule(T->C->m, m, T->C->tm, NULL, &Err);
        delete m;
        if(failed)
            terra_reporterror(T, "llvm: %s\n", Err.c_str());
    } else {
        std::string Err;
        if(sys::DynamicLibrary::LoadLibraryPermanently(filename,&Err)) {
            terra_reporterror(T, "llvm: %s\n", Err.c_str());
        }
    }
    return 0;
}

static int terra_dumpmodule(lua_State * L) {
    terra_State * T = terra_getstate(L, 1);
    T->C->m->dump();
    return 0;
}



