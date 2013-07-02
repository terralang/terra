/* See Copyright Notice in ../LICENSE.txt */

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

#ifdef _WIN32
#include <io.h>
#include <time.h>
#include <Windows.h>
#undef interface
#else
#include <unistd.h>
#include <sys/time.h>
#endif

#include <cmath>
#include <sstream>
#include "llvmheaders.h"
#include "tllvmutil.h"
#include "tcompilerstate.h" //definition of terra_CompilerState which contains LLVM state
#include "tobj.h"
#include "tinline.h"
#include "llvm/Support/ManagedStatic.h"
#include "llvm/ExecutionEngine/MCJIT.h"
#include "llvm/Bitcode/ReaderWriter.h"
#include "llvm/Support/Atomic.h"

using namespace llvm;


#define TERRALIB_FUNCTIONS(_) \
    _(codegen,1) /*entry point from lua into compiler to generate LLVM for a function, other functions it calls may not yet exist*/\
    _(optimize,1) /*entry point from lua into compiler to perform optimizations at the function level, passed an entire strongly connected component of functions\
                    all callee's of these functions that are not in this scc have already been optimized*/\
    _(jit,1) /*entry point from lua into compiler to actually invoke the JIT by calling getPointerToFunction*/\
    _(createglobal,1) \
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
    virtual void NotifyFunctionEmitted (const Function & f, void * data, size_t sz, const EmittedFunctionDetails &) {
        T->C->functionsizes[&f] = sz;
    }
};

static double CurrentTimeInSeconds() {
#ifdef _WIN32
    return time(NULL);
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
    obj->obj("stats",&stats);
    double end = CurrentTimeInSeconds();
    lua_pushnumber(L, end - begin);
    stats.setfield(name);
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
    Function** gchandle = (Function**) lua_newuserdata(L,sizeof(Function*));
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

        AddLLVMOptions(1,"-x86-asm-syntax=intel");
        InitializeNativeTarget();
        InitializeNativeTargetAsmPrinter();
        InitializeNativeTargetAsmParser();
    } else { 
        if(!llvm_is_multithreaded()) {
            if(!llvm_start_multithreaded()) {
                terra_pusherror(T,"llvm failed to start multi-threading\n");
                success = false;
            }
        }
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
    unsigned EAX,EBX,ECX,EDX;
    llvm::X86_MC::GetCpuIDAndInfo(1,&EAX,&EBX,&ECX,&EDX);
    return (ECX >> 28) & 1;
}

int terra_compilerinit(struct terra_State * T) {
    
    lua_getfield(T->L,LUA_GLOBALSINDEX,"terra");
    
    if(!OneTimeInit(T))
        return LUA_ERRRUN;

    #define REGISTER_FN(name,isclo) RegisterFunction(T,#name,isclo,terra_##name);
    TERRALIB_FUNCTIONS(REGISTER_FN)
    #undef REGISTER_FN

#ifdef LLVM_3_2
    lua_pushstring(T->L,"3.2");
#else
    lua_pushstring(T->L,"3.1");
#endif

    lua_setfield(T->L,-2, "llvmversion");
    
    lua_pop(T->L,1); //remove terra from stack
    
    T->C = (terra_CompilerState*) malloc(sizeof(terra_CompilerState));
    memset(T->C, 0, sizeof(terra_CompilerState));
    
    T->C->ctx = new LLVMContext();
    T->C->m = new Module("terra",*T->C->ctx);
    
    TargetOptions options;
    CodeGenOpt::Level OL = CodeGenOpt::Aggressive;
    std::string Triple = llvm::sys::getDefaultTargetTriple();
    std::string err;
    const Target *TheTarget = TargetRegistry::lookupTarget(Triple, err);
    TargetMachine * TM = TheTarget->createTargetMachine(Triple, "", HostHasAVX() ? "+avx" : "", options,Reloc::Default,CodeModel::Default,OL);
    T->C->td = TM->TARGETDATA(get)();
    
    
    T->C->ee = EngineBuilder(T->C->m).setErrorStr(&err).setEngineKind(EngineKind::JIT).setAllocateGVsWithCode(false).create();
    if (!T->C->ee) {
        terra_pusherror(T,"llvm: %s\n",err.c_str());
        return LUA_ERRRUN;
    }
    
    T->C->fpm = new FunctionPassManager(T->C->m);

    llvmutil_addtargetspecificpasses(T->C->fpm, TM);
    OptInfo info; //TODO: make configurable from terra
    llvmutil_addoptimizationpasses(T->C->fpm,&info);
    
    
    
    if(!TheTarget) {
        terra_pusherror(T,"llvm: %s\n",err.c_str());
        return LUA_ERRRUN;
    }
    
    
    T->C->tm = TM;
    T->C->mi = createManualFunctionInliningPass(T->C->td);
    T->C->mi->doInitialization();
    T->C->jiteventlistener = new DisassembleFunctionListener(T);
    T->C->ee->RegisterJITEventListener(T->C->jiteventlistener);
    
    return 0;
}

struct TType { //contains llvm raw type pointer and any metadata about it we need
    Type * type;
    bool issigned;
    bool islogical;
    bool incomplete; // does this aggregate type or its children include an incomplete struct
};

struct TerraCompiler;


static void GetStructEntries(Obj * typ, Obj * entries) {
    Obj layout;
    if(!typ->obj("cachedlayout",&layout)) {
        assert(!"typechecked failed to complete type needed by the compiler, this is a bug.");
    }
    layout.obj("entries",entries);
}

//functions that handle the details of the x86_64 ABI (this really should be handled by LLVM...)
struct CCallingConv {
    terra_State * T;
    lua_State * L;
    terra_CompilerState * C;
    IRBuilder<> * B;
    
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
        int nargs; //number of arguments this value will produce in parameter list
        Type * type; //orignal type for the object
        StructType * cctype; //if type == C_AGGREGATE_REG, this struct that holds a list of the values that goes into the registers
        Argument() {}
        Argument(ArgumentKind kind, Type * type, int nargs = 1, StructType * cctype = NULL) {
            this->kind = kind;
            this->type = type;
            this->nargs = nargs;
            this->cctype = cctype;
        }
    };
    
    struct Classification {
        int nreturns; //number of return values
        Argument returntype; //classification of return type (if nreturns > 1) this will always be an C_AGGREGATE_* each member holding 1 return value
        std::vector<Argument> paramtypes;
    };
    
    void init(terra_State * T, terra_CompilerState * C, IRBuilder<> * B) {
        this->T = T;
        this->L = T->L;
        this->C = C;
        this->B = B;
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
            
            Type * fieldtype = GetType(&vt)->type;
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
        DEBUG_ONLY(T) {
            printf("Struct Layout Is:\n");
            st->dump();
            printf("\nEnd Layout\n");
        }
    }
    bool LookupTypeCache(Obj * typ, TType ** t) {
        *t = (TType*) typ->ud("llvm_type"); //try to look up the cached type
        if(*t == NULL) {
            *t = (TType*) lua_newuserdata(L,sizeof(TType));
            memset(*t,0,sizeof(TType));
            typ->setfield("llvm_type");
            assert(*t != NULL);
            return false;
        }
        return true;
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
    StructType * CreateStruct(Obj * typ) {
        //check to see if it was initialized externally first
        StructType * st;
        if(typ->hasfield("llvm_name")) {
            const char * llvmname = typ->string("llvm_name");
            st = C->m->getTypeByName(llvmname);
        } else {
            st = StructType::create(*C->ctx,typ->asstring("displayname"));
        }
        return st;
    }
    Type * FunctionPointerType() {
        return Ptr(Type::getInt8PtrTy(*C->ctx));
    }
    TType * GetTypeIncomplete(Obj * typ) {
        TType * t = NULL;
        if(!LookupTypeCache(typ, &t)) {
            assert(t);
            switch(typ->kind("kind")) {
                case T_pointer: {
                    Obj base;
                    typ->obj("type",&base);
                    if(T_functype == base.kind("kind")) {
                        t->type = FunctionPointerType();
                    } else {
                        TType * baset = GetTypeIncomplete(&base);
                        t->type = PointerType::getUnqual(baset->type);
                    }
                } break;
                case T_array: {
                    Obj base;
                    typ->obj("type",&base);
                    int N = typ->number("N");
                    TType * baset = GetTypeIncomplete(&base);
                    t->type = ArrayType::get(baset->type, N);
                    t->incomplete = baset->incomplete;
                } break;
                case T_struct: {
                    StructType * st = CreateStruct(typ);
                    t->type = st;
                    t->incomplete = st->isOpaque();
                } break;
                case T_functype: {
                    t->type = CreateFunctionType(typ);
                } break;
                case T_vector: {
                    Obj base;
                    typ->obj("type",&base);
                    int N = typ->number("N");
                    TType * ttype = GetTypeIncomplete(&base); //vectors can only contain primitives, so the type must be complete
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
                default: {
                    printf("kind = %d, %s\n",typ->kind("kind"),tkindtostr(typ->kind("kind")));
                    terra_reporterror(T,"type not understood or not primitive\n");
                } break;
            }
        }
        assert(t && t->type);
        return t;
    }
    
    TType * GetType(Obj * typ) {
        TType * t = GetTypeIncomplete(typ);
        if(t->incomplete) {
            assert(t->type->isAggregateType());
            switch(typ->kind("kind")) {
                case T_struct: {
                    LayoutStruct(cast<StructType>(t->type), typ);
                } break;
                case T_array: {
                    Obj base;
                    typ->obj("type",&base);
                    GetType(&base); //force base type to be completed
                } break;
                default:
                    terra_reporterror(T,"type marked incomplete is not an array or struct\n");
            }
        }
        t->incomplete = false;
        return t;
    }
    
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
        Type * t = GetType(type)->type;
        int entry = offset / 8;
        if(t->isVectorTy()) //we don't handle structures with vectors in them yet
            classes[entry] = C_MEMORY;
        else if(t->isFloatingPointTy())
            classes[entry] = Meet(classes[entry],C_SSE);
        else if(t->isIntegerTy() || t->isPointerTy())
            classes[entry] = Meet(classes[entry],C_INTEGER);
        else if(t->isStructTy()) {
            StructType * st = cast<StructType>(GetType(type)->type);
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
            ArrayType * at = cast<ArrayType>(GetType(type)->type);
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
        TType * t = GetType(type);
        
        if(!t->type->isAggregateType()) {
            if(t->type->isFloatingPointTy() || t->type->isVectorTy())
                ++*usedfloat;
            else
                ++*usedint;
            return Argument(C_PRIMITIVE,t->type);
        }
        
        int sz = C->td->getTypeAllocSize(t->type);
        if(!ValidAggregateSize(sz)) {
            return Argument(C_AGGREGATE_MEM,t->type);
        }
        
        RegisterClass classes[] = {C_NO_CLASS, C_NO_CLASS};
        
        int sizes[] = { std::min(sz,8), std::max(0,sz - 8) };
        MergeValue(classes, 0, type);
        if(classes[0] == C_MEMORY || classes[1] == C_MEMORY) {
            return Argument(C_AGGREGATE_MEM,t->type);
        }
        int nfloat = (classes[0] == C_SSE) + (classes[1] == C_SSE);
        int nint = (classes[0] == C_INTEGER) + (classes[1] == C_INTEGER);
        if (sz > 8 && (*usedfloat + nfloat > 8 || *usedint + nint > 6)) {
            return Argument(C_AGGREGATE_MEM,t->type);
        }
        
        *usedfloat += nfloat;
        *usedint += nint;
        
        std::vector<Type*> elements;
        elements.push_back(TypeForClass(sizes[0], classes[0]));
        if(sizes[1] > 0) {
            elements.push_back(TypeForClass(sizes[1],classes[1]));
        }
        return Argument(C_AGGREGATE_REG,t->type,elements.size(),
                        StructType::get(*C->ctx,elements));
    }
    
    void Classify(Obj * ftype, Obj * params, Classification * info) {
        Obj returns;
        ftype->obj("returns",&returns);
        info->nreturns = returns.size();
        
        if (info->nreturns == 0) {
            info->returntype = Argument(C_PRIMITIVE,Type::getVoidTy(*C->ctx));
        } else {
            Obj returnobj;
            ftype->obj("returnobj",&returnobj);
            int zero = 0;
            info->returntype = ClassifyArgument(&returnobj, &zero, &zero);
        }
        
        int nfloat = 0;
        int nint = info->returntype.kind == C_AGGREGATE_MEM ? 1 : 0; /*sret consumes RDI for the return value pointer so it counts towards the used integer registers*/
        int N = params->size();
        for(int i = 0; i < N; i++) {
            Obj elem;
            params->objAt(i,&elem);
            info->paramtypes.push_back(ClassifyArgument(&elem,&nfloat,&nint));
        }
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
    
    Attributes SRetAttr() {
        #ifdef LLVM_3_2
            AttrBuilder builder;
            builder.addAttribute(Attributes::StructRet);
            builder.addAttribute(Attributes::NoAlias);
            return Attributes::get(*C->ctx,builder);
        #else
            return Attributes(Attribute::StructRet | Attribute::NoAlias);
        #endif
    }
    Attributes ByValAttr() {
        #ifdef LLVM_3_2
            AttrBuilder builder;
            builder.addAttribute(Attributes::ByVal);
            return Attributes::get(*C->ctx,builder);
        #else
            return Attributes(Attribute::ByVal);
        #endif
    }
    
    template<typename FnOrCall>
    void AttributeFnOrCall(FnOrCall * r, Classification * info) {
        int argidx = 1;
        if(info->returntype.kind == C_AGGREGATE_MEM) {
            r->addAttribute(argidx,SRetAttr());
            argidx++;
        }
        for(int i = 0; i < info->paramtypes.size(); i++) {
            Argument * v = &info->paramtypes[i];
            if(v->kind == C_AGGREGATE_MEM) {
                #ifndef _WIN32
                r->addAttribute(argidx,ByValAttr());
                #endif
            }
            argidx += v->nargs;
        }
    }
    
    Function * CreateFunction(Obj * ftype, const char * name) {
        TType * llvmtyp = GetType(ftype);
        Function * fn = Function::Create(cast<FunctionType>(llvmtyp->type), Function::ExternalLinkage,name, C->m);
        Classification * info = ClassifyFunction(ftype);
        AttributeFnOrCall(fn,info);
        return fn;
    }
    
    PointerType * Ptr(Type * t) {
        return PointerType::getUnqual(t);
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
                case C_PRIMITIVE:
                    B->CreateStore(ai,v);
                    ++ai;
                    break;
                case C_AGGREGATE_MEM:
                    //TODO: check that LLVM optimizes this copy away
                    B->CreateStore(B->CreateLoad(ai),v);
                    ++ai;
                    break;
                case C_AGGREGATE_REG: {
                    Value * dest = B->CreateBitCast(v,Ptr(p->cctype));
                    for(int j = 0; j < p->nargs; j++) {
                        B->CreateStore(ai,B->CreateConstGEP2_32(dest, 0, j));
                        ++ai;
                    }
                } break;
            }
        }
    }
    void FillAggregate(Value * dest, std::vector<Value *> * results) {
        if(results->size() == 1) {
            B->CreateStore((*results)[0],dest);
        } else {
            for(size_t i = 0; i < results->size(); i++) {
                B->CreateStore((*results)[i],B->CreateConstGEP2_32(dest,0,i));
            }
        }
    }
    void EmitReturn(Obj * ftype, Function * function, std::vector<Value*> * results) {
        Classification * info = ClassifyFunction(ftype);
        assert(results->size() == info->nreturns);
        ArgumentKind kind = info->returntype.kind;
        
        if(info->nreturns == 0) {
            B->CreateRetVoid();
        } else if(C_PRIMITIVE == kind) {
            assert(results->size() == 1);
            B->CreateRet((*results)[0]);
        } else if(C_AGGREGATE_MEM == kind) {
            FillAggregate(function->arg_begin(),results);
            B->CreateRetVoid();
        } else if(C_AGGREGATE_REG == kind) {
            Value * dest = CreateAlloca(info->returntype.type);
            FillAggregate(dest,results);
            Value *  result = B->CreateBitCast(dest,Ptr(info->returntype.cctype));
            if(info->returntype.nargs == 1)
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
            arguments.push_back(CreateAlloca(info.returntype.type));
        }
        
        for(size_t i = 0; i < info.paramtypes.size(); i++) {
            Argument * a = &info.paramtypes[i];
            Value * actual = (*actuals)[i];
            switch(a->kind) {
                case C_PRIMITIVE:
                    arguments.push_back(actual);
                    break;
                case C_AGGREGATE_MEM: {
                    Value * scratch = CreateAlloca(a->type);
                    B->CreateStore(actual,scratch);
                    arguments.push_back(scratch);
                } break;
                case C_AGGREGATE_REG: {
                    Value * scratch = CreateAlloca(a->type);
                    B->CreateStore(actual,scratch);
                    Value * casted = B->CreateBitCast(scratch,Ptr(a->cctype));
                    for(size_t j = 0; j < a->nargs; j++) {
                        arguments.push_back(B->CreateLoad(B->CreateConstGEP2_32(casted,0,j)));
                    }
                } break;
            }
            
        }
        
        //emit call
        //function pointers are stored as &int8 to avoid calling convension issues
        //cast it back to the real pointer type right before calling it
        TType * llvmftype = GetType(ftype);
        callee = B->CreateBitCast(callee,Ptr(llvmftype->type));
        CallInst * call = B->CreateCall(callee, arguments);
        //annotate call with byval and sret
        AttributeFnOrCall(call,&info);
        
        //unstage results
        if(info.nreturns == 0) {
            return call;
        } else if(C_PRIMITIVE == info.returntype.kind) {
            return call;
        } else {
            Value * aggregate;
            if(C_AGGREGATE_MEM == info.returntype.kind) {
                aggregate = arguments[0];
            } else { //C_AGGREGATE_REG
                aggregate = CreateAlloca(info.returntype.type);
                Value * casted = B->CreateBitCast(aggregate,Ptr(info.returntype.cctype));
                if(info.returntype.nargs == 1)
                    casted = B->CreateConstGEP2_32(casted, 0, 0);
                B->CreateStore(call,casted);
            }
            
            if(info.nreturns == 1) {
                return B->CreateLoad(aggregate);
            } else {
                //multireturn
                return aggregate;
            }
        }
        
    }
    Value * EmitExtractReturn(Value * aggregate, int nreturns, int idx) {
        assert(nreturns != 0);
        if(nreturns > 1) {
            return B->CreateLoad(B->CreateConstGEP2_32(aggregate, 0, idx));
        } else {
            return aggregate;
        }
    }
    Type * CreateFunctionType(Obj * typ) {

        std::vector<Type*> arguments;
        bool isvararg = typ->boolean("isvararg");
        
        Classification * info = ClassifyFunction(typ);
        
        Type * rt = info->returntype.type;
        if(info->returntype.kind == C_AGGREGATE_REG) {
            if(info->returntype.nargs == 1)
                rt = info->returntype.cctype->getElementType(0);
            else
                rt = info->returntype.cctype;
        } else if(info->returntype.kind == C_AGGREGATE_MEM) {
            rt = Type::getVoidTy(*C->ctx);
            arguments.push_back(Ptr(info->returntype.type));
        }
        
        for(size_t i = 0; i < info->paramtypes.size(); i++) {
            Type * t;
            Argument * a = &info->paramtypes[i];
            switch(a->kind) {
                case C_PRIMITIVE:
                    arguments.push_back(a->type);
                    break;
                case C_AGGREGATE_MEM:
                    arguments.push_back(Ptr(a->type));
                    break;
                case C_AGGREGATE_REG: {
                    for(size_t j = 0; j < a->nargs; j++) {
                        arguments.push_back(a->cctype->getElementType(j));
                    }
                } break;
            }
        }
        
        return FunctionType::get(rt,arguments,isvararg);
    }
    
    void EnsureTypeIsComplete(Obj * typ) {
        GetType(typ);
    }
    
    AllocaInst *CreateAlloca(Type *Ty, Value *ArraySize = 0, const Twine &Name = "") {
        BasicBlock * entry = &B->GetInsertBlock()->getParent()->getEntryBlock();
        IRBuilder<> TmpB(entry,
                         entry->begin()); //make sure alloca are at the beginning of the function
                                          //this is needed because alloca's that do not dominate the
                                          //function do weird things
        return TmpB.CreateAlloca(Ty,ArraySize,Name);
    }
};

static Constant * GetConstant(CCallingConv * CC, Obj * v) {
    lua_State * L = CC->L;
    terra_CompilerState * C = CC->C;
    Obj t;
    v->obj("type", &t);
    TType * typ = CC->GetType(&t);
    ConstantFolder B;
    if(typ->type->isAggregateType()) { //if the constant is a large value, we make a single global variable that holds that value
        Type * ptyp = PointerType::getUnqual(typ->type);
        GlobalValue * gv = (GlobalVariable*) v->ud("llvm_value");
        if(gv == NULL) {
            v->pushfield("object");
            const void * data = lua_topointer(L,-1);
            assert(data);
            lua_pop(L,1); // remove pointer
            size_t size = C->td->getTypeAllocSize(typ->type);
            size_t align = C->td->getPrefTypeAlignment(typ->type);
            Constant * arr = ConstantDataArray::get(*C->ctx,ArrayRef<uint8_t>((uint8_t*)data,size));
            gv = new GlobalVariable(*C->m, arr->getType(),
                                    true, GlobalValue::PrivateLinkage,
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
            return ConstantFP::get(typ->type, *(float*)data);
        } else if(typ->type->isDoubleTy()) {
            return ConstantFP::get(typ->type, *(double*)data);
        } else if(typ->type->isPointerTy()) {
            Constant * ptrint = ConstantInt::get(C->td->getIntPtrType(*C->ctx), *(intptr_t*)data);
            return ConstantExpr::getIntToPtr(ptrint, typ->type);
        } else {
            typ->type->dump();
            printf("NYI - constant load\n");
            abort();
        }
    }
}


static GlobalVariable * GetGlobalVariable(CCallingConv * CC, Obj * global, const char * name) {
    GlobalVariable * gv = (GlobalVariable *) global->ud("value");
    if (gv == NULL) {
        Obj t;
        global->obj("type",&t);
        Type * typ = CC->GetType(&t)->type;
        
        Constant * llvmconstant = UndefValue::get(typ);
        Obj constant;
        if(global->obj("initializer",&constant)) {
            llvmconstant = GetConstant(CC,&constant);
        }
        gv = new GlobalVariable(*CC->C->m, typ, false, GlobalValue::ExternalLinkage, llvmconstant, name);
        lua_pushlightuserdata(CC->L, gv);
        global->setfield("value");
        //TODO: eventually the initialization constant can be a constant expression that hasn't been defined yet
        //so this would not be safe to do here
        void * data = CC->C->ee->getPointerToGlobal(gv);
        assert(data);
        lua_pushlightuserdata(CC->L,data);
        global->setfield("llvm_ptr");
    }
    void ** data = (void**) CC->C->ee->getPointerToGlobal(gv);
    assert(gv != NULL);
    return gv;
}


static int terra_deletefunction(lua_State * L);

struct TerraCompiler {
    lua_State * L;
    terra_State * T;
    terra_CompilerState * C;
    IRBuilder<> * B;
    Obj funcobj;
    Function * func;
    TType * func_type;
    CCallingConv CC;
    
    TType * getType(Obj * v) {
        return CC.GetType(v);
    }
    TType * typeOfValue(Obj * v) {
        Obj t;
        v->obj("type",&t);
        return getType(&t);
    }
    
    AllocaInst * allocVar(Obj * v) {
        AllocaInst * a = CC.CreateAlloca(typeOfValue(v)->type,0,v->asstring("name"));
        lua_pushlightuserdata(L,a);
        v->setfield("value");
        return a;
    }
    
    void getOrCreateFunction(Obj * funcobj, Function ** rfn, TType ** rtyp) {
        Function * fn = (Function *) funcobj->ud("llvm_function");
        Obj ftype;
        funcobj->obj("type",&ftype);
        *rtyp = getType(&ftype);
        if(!fn) {
            const char * name = funcobj->string("name");
            
            fn = CC.CreateFunction(&ftype, name);
            
            if(funcobj->boolean("alwaysinline")) {
                fn->ADDFNATTR(AlwaysInline);
            }
            lua_pushlightuserdata(L,fn);
            funcobj->setfield("llvm_function");

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
        }
        *rfn = fn;
    }
    
    void run(terra_State * _T, int ref_table) {
        double begin = CurrentTimeInSeconds();
        T = _T;
        L = T->L;
        C = T->C;
        B = new IRBuilder<>(*C->ctx);
        CC.init(T, C, B);
        
        lua_pushvalue(T->L,-2); //the original argument
        funcobj.initFromStack(T->L, ref_table);
        
        getOrCreateFunction(&funcobj,&func,&func_type);
        
        BasicBlock * entry = BasicBlock::Create(*C->ctx,"entry",func);
        
        B->SetInsertPoint(entry);
        
        Obj typedtree;
        Obj parameters;
        
        funcobj.obj("typedtree",&typedtree);
        typedtree.obj("parameters",&parameters);
        
        Obj ftype;
        funcobj.obj("type",&ftype);
        
        int N = parameters.size();
        std::vector<Value *> parametervars;
        for(size_t i = 0; i < N; i++) {
            Obj p;
            parameters.objAt(i,&p);
            parametervars.push_back(allocVar(&p));
        }
        
        CC.EmitEntry(&ftype, func, &parametervars);
         
        Obj body;
        typedtree.obj("body",&body);
        emitStmt(&body);
        //if there no terminating return statment, we need to insert one
        //if there was a Return, then this block is dead and will be cleaned up
        emitReturnUndef();
        
        DEBUG_ONLY(T) {
            func->dump();
        }
        verifyFunction(*func);
        
        RecordTime(&funcobj, "llvmgen", begin);
        //cleanup -- ensure we left the stack the way we started
        assert(lua_gettop(T->L) == ref_table);
        delete B;
    }
    
    Value * emitAddressOf(Obj * exp) {
        Value * v = emitExp(exp,false);
        if(exp->boolean("lvalue"))
            return v;
        Value * addr = CC.CreateAlloca(typeOfValue(exp)->type);
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
    Value * emitCompare(Obj * exp, Obj * ao, Value * a, Value * b) {
        TType * t = typeOfValue(ao);
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
        
        switch(exp->kind("operator")) {
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
        Value * result = CC.CreateAlloca(t->type);
        Value * a = emitExp(ao);
        Value * acond = emitCond(a);
        BasicBlock * stmtB = createAndInsertBB("logicalcont");
        BasicBlock * emptyB = createAndInsertBB("logicalnop");
        BasicBlock * mergeB = createAndInsertBB("merge");
        B->CreateCondBr(acond, (isAnd) ? stmtB : emptyB, (isAnd) ? emptyB : stmtB);
        setInsertBlock(stmtB);
        Value * b = emitExp(bo);
        B->CreateStore(b, result);
        B->CreateBr(mergeB);
        setInsertBlock(emptyB);
        B->CreateStore(a, result);
        B->CreateBr(mergeB);
        setInsertBlock(mergeB);
        return B->CreateLoad(result, "logicalop");
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
    void EnsurePointsToCompleteType(Obj * ptrTy) {
        Obj objTy;
        if(ptrTy->obj("type",&objTy)) {
            CC.EnsureTypeIsComplete(&objTy);
        } //otherwise it is niltype and already complete
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
            EnsurePointsToCompleteType(&aot);
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
                Value * v = emitCompare(exp,ao,a,b);
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
        Value * output = CC.CreateAlloca(to->type);
        
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
                if(fsize > tsize) {
                    return B->CreateTrunc(exp, to->type);
                } else if(fsize == tsize) {
                    return exp; //no-op in llvm since its types are not signed
                } else {
                    if(from->issigned) {
                        return B->CreateSExt(exp, to->type);
                    } else {
                        return B->CreateZExt(exp, to->type);
                    }
                }
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
        for(int i = 0; i < vt->getNumElements(); i++)
            result = B->CreateInsertElement(result, v, ConstantInt::get(integerType, i));
        return result;
    }
    Value * emitStructSelect(Obj * structType, Value * structPtr, int index) {

        assert(structPtr->getType()->isPointerTy());
        PointerType * objTy = cast<PointerType>(structPtr->getType());
        assert(objTy->getElementType()->isStructTy());
        CC.EnsureTypeIsComplete(structType);
        
        Obj layout;
        GetStructEntries(structType,&layout);
        
        Obj entry;
        layout.objAt(index,&entry);
        
        int allocindex = entry.number("allocation");
        
        Value * addr = B->CreateConstGEP2_32(structPtr,0,allocindex);
        
        if (entry.boolean("inunion")) {
            Obj entryType;
            entry.obj("type",&entryType);
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
            return GetGlobalVariable(&CC,&def,exp->asstring("name"));
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
            CC.EnsureTypeIsComplete(&type);
            raw = B->CreateLoad(raw);
        }
        return raw;
    }
    /* alignment for load

    */
    
    Value * emitExpRaw(Obj * exp) {
        switch(exp->kind("kind")) {
            case T_var:  {
                return variableFromDefinition(exp);
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
                    EnsurePointsToCompleteType(&aggTypeO);
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
                    Obj objType;
                    if(!type.obj("type",&objType)) {
                        //null pointer type
                        return ConstantPointerNull::get(pt);
                    }
                    Type * objT = getType(&objType)->type;
                
                    if(objT->isFunctionTy()) {
                        Obj func;
                        exp->obj("value",&func);
                        TType * ftyp;
                        Function * fn;
                        getOrCreateFunction(&func,&fn,&ftyp);
                        //functions are represented with &int8 pointers to avoid
                        //calling convension issues, so cast the literal to this type now
                        return B->CreateBitCast(fn,CC.FunctionPointerType());
                    } else if(objT->isIntegerTy(8)) {
                        exp->pushfield("value");
                        size_t len;
                        const char * rawstr = lua_tolstring(L,-1,&len);
                        Value * str = B->CreateGlobalString(StringRef(rawstr,len));
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
                return GetConstant(&CC,&value);
            } break;
            case T_luafunction: {
                Obj type,objType;
                exp->obj("type",&type);
                type.obj("type", &objType);
                
                FunctionType * fntyp = cast<FunctionType>(getType(&objType)->type);
                assert(fntyp);
                Function * fn = Function::Create(fntyp, Function::ExternalLinkage,"", C->m);
                void * ptr = exp->ud("fptr");
                C->ee->addGlobalMapping(fn, ptr); //if we deserialize this function it will be necessary to relink this to the lua runtime
                return fn;
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
            case T_extractreturn: {
                return emitExtractReturn(exp);
            } break;
            case T_treelist: {
                std::vector<Value*> values;
                emitTreeList(exp, false, &values);
                return (values.size() == 0) ? NULL : values[0];
            } break;
            case T_select: {
                Obj obj,typ;
                exp->obj("value",&obj);
                TType * vt = typeOfValue(&obj);
                
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
                
                Value * result = CC.CreateAlloca(typeOfValue(exp)->type);
                std::vector<Value *> values;
                emitTreeList(&expressions,true,&values);
                for(size_t i = 0; i < values.size(); i++) {
                    Value * addr = B->CreateConstGEP2_32(result,0,i);
                    B->CreateStore(values[i],addr);
                }
                return B->CreateLoad(result);
            } break;
            case T_vectorconstructor: {
                Obj expressions;
                exp->obj("expressions",&expressions);
                std::vector<Value *> values;
                emitTreeList(&expressions,true,&values);
                TType * vecType = typeOfValue(exp);
                Value * vec = UndefValue::get(vecType->type);
                Type * intType = Type::getInt32Ty(*C->ctx);
                for(size_t i = 0; i < values.size(); i++) {
                    vec = B->CreateInsertElement(vec, values[i], ConstantInt::get(intType, i));
                }
                return vec;
            } break;
            case T_intrinsic: {
                Obj arguments;
                exp->obj("arguments",&arguments);
                std::vector<Value *> values;
                emitTreeList(&arguments,true,&values);
                Obj itypeObjPtr;
                exp->obj("intrinsictype",&itypeObjPtr);
                Obj itypeObj;
                itypeObjPtr.obj("type",&itypeObj);
                TType * itype = getType(&itypeObj);
                const char * name = exp->string("name");
                FunctionType * fntype = cast<FunctionType>(itype->type);
                Value * fn = C->m->getOrInsertFunction(name, fntype);
                return B->CreateCall(fn, values);
            }
            case T_attrload: {
                Obj addr,type,attr;
                exp->obj("type",&type);
                exp->obj("address",&addr);
                exp->obj("attributes",&attr);
                CC.EnsureTypeIsComplete(&type);
                LoadInst * l = B->CreateLoad(emitExp(&addr));
                if(attr.hasfield("alignment")) {
                    int alignment = attr.number("alignment");
                    l->setAlignment(alignment);
                }
                return l;
            } break;
            default: {
                exp->dump();
                assert(!"NYI - exp");
            } break;
        }
    }
    BasicBlock * createBB(const char * name) {
        BasicBlock * bb = BasicBlock::Create(*C->ctx, name);
        return bb;
    }
    BasicBlock * createAndInsertBB(const char * name) {
        BasicBlock * bb = createBB(name);
        insertBB(bb);
        return bb;
    }
    void insertBB(BasicBlock * bb) {
        func->getBasicBlockList().push_back(bb);
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
        Value * v = emitCond(&cond);
        BasicBlock * thenBB = createAndInsertBB("then");
        BasicBlock * continueif = createBB("else");
        B->CreateCondBr(v, thenBB, continueif);
        
        setInsertBlock(thenBB);
        
        emitStmt(&body);
        B->CreateBr(footer);
        insertBB(continueif);
        setInsertBlock(continueif);
        
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
            bb = createBB(lbl->string("labelname"));
            lua_pushlightuserdata(L,bb);
            lbl->setfield("basicblock");
        }
        return bb;
    }
    Value * emitCall(Obj * call) {
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
        emitTreeList(&paramlist,true,&actuals);
        
        return CC.EmitCall(&fntyp,&paramtypes, fn, &actuals);
    }
    
    void emitReturnUndef() {
        Type * rt = func->getReturnType();
        if(rt->isVoidTy()) {
            B->CreateRetVoid();
        } else {
            B->CreateRet(UndefValue::get(rt));
        }
    }
    void emitTreeList(Obj * treelist, bool loadlvalue, std::vector<Value*> * results) {
        Obj types;
        treelist->obj("types",&types);
        int N = types.size();
        Obj next;
        treelist->push();
        treelist->fromStack(&next);
        do {
            Obj stmts;
            if(next.obj("statements",&stmts)) {
                int NS = stmts.size();
                for(int i = 0; i < NS; i++) {
                    Obj s;
                    stmts.objAt(i,&s);
                    emitStmt(&s);
                }
            }
            Obj exprs;
            if(next.obj("expressions",&exprs)) {
                int NE = exprs.size();
                for(int i = 0; i < NE; i++) {
                    Obj e;
                    exprs.objAt(i,&e);
                    Value * r = emitExp(&e,loadlvalue);
                    if(results && results->size() < N)
                        results->push_back(r);
                }
            }
        } while(next.obj("next", &next));
    }
    
    Value * emitExtractReturn(Obj * exp) {
        int idx = exp->number("index");
        Obj fncall;
        Obj rtypes;
        exp->obj("fncall", &fncall);
        fncall.obj("returntypes",&rtypes);
        //TODO: this is a bug, it is possible the user did something really wrong
        //cause an extract return to escape the scope of the value, which will make this repeat the
        //function call.
        //we need to check this earlier in the pipeline
        Value * fnresult = (Value*) fncall.ud("returnvalue");
        assert(fnresult);
        return CC.EmitExtractReturn(fnresult,rtypes.size(),idx);
    }
    void startDeadCode() {
        BasicBlock * bb = createAndInsertBB("dead");
        setInsertBlock(bb);
    }
    
    void emitStmt(Obj * stmt) {
        T_Kind kind = stmt->kind("kind");
        switch(kind) {
            case T_block: {
                Obj treelist;
                stmt->obj("body",&treelist);
                emitStmt(&treelist);
            } break;
            case T_treelist: {
                emitTreeList(stmt, false, NULL);
            } break;
            case T_return: {
                Obj exps;
                stmt->obj("expressions",&exps);
                
                std::vector<Value *> results;
                emitTreeList(&exps, true, &results);
                Obj ftype;
                funcobj.obj("type",&ftype);
                CC.EmitReturn(&ftype,func,&results);
                startDeadCode();
            } break;
            case T_label: {
                BasicBlock * bb = getOrCreateBlockForLabel(stmt);
                B->CreateBr(bb);
                insertBB(bb);
                setInsertBlock(bb);
            } break;
            case T_goto: {
                Obj lbl;
                stmt->obj("definition",&lbl);
                BasicBlock * bb = getOrCreateBlockForLabel(&lbl);
                B->CreateBr(bb);
                startDeadCode();
            } break;
            case T_break: {
                Obj def;
                stmt->obj("breaktable",&def);
                BasicBlock * breakpoint = (BasicBlock *) def.ud("value");
                assert(breakpoint);
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
                
                Value * v = emitCond(&cond);
                BasicBlock * loopBody = createAndInsertBB("whilebody");
    
                BasicBlock * merge = createBB("merge");
                
                setBreaktable(stmt,merge);
                
                B->CreateCondBr(v, loopBody, merge);
                
                setInsertBlock(loopBody);
                
                emitStmt(&body);
                
                B->CreateBr(condBB);
                
                insertBB(merge);
                setInsertBlock(merge);
            } break;
            case T_if: {
                Obj branches;
                stmt->obj("branches",&branches);
                int N = branches.size();
                BasicBlock * footer = createBB("merge");
                for(int i = 0; i < N; i++) {
                    Obj branch;
                    branches.objAt(i,&branch);
                    emitIfBranch(&branch,footer);
                }
                Obj orelse;
                if(stmt->obj("orelse",&orelse))
                    emitStmt(&orelse);
                B->CreateBr(footer);
                insertBB(footer);
                setInsertBlock(footer);
            } break;
            case T_repeat: {
                Obj cond,body;
                stmt->obj("condition",&cond);
                stmt->obj("body",&body);
                
                BasicBlock * loopBody = createAndInsertBB("repeatbody");
                BasicBlock * merge = createBB("merge");
                
                setBreaktable(stmt,merge);
                
                B->CreateBr(loopBody);
                setInsertBlock(loopBody);
                emitStmt(&body);
                Value * c = emitCond(&cond);
                B->CreateCondBr(c, merge, loopBody);
                insertBB(merge);
                setInsertBlock(merge);
                
            } break;
            case T_defvar: {
                std::vector<Value *> rhs;
                
                Obj inits;
                bool has_inits = stmt->obj("initializers",&inits);
                if(has_inits)
                    emitTreeList(&inits, true, &rhs);
                
                Obj vars;
                stmt->obj("variables",&vars);
                int N = vars.size();
                for(int i = 0; i < N; i++) {
                    Obj v;
                    vars.objAt(i,&v);
                    Value * addr = allocVar(&v);
                    if(has_inits)
                        B->CreateStore(rhs[i],addr);
                }
            } break;
            case T_assignment: {
                std::vector<Value *> rhsexps;
                Obj rhss;
                stmt->obj("rhs",&rhss);
                emitTreeList(&rhss,true,&rhsexps);
                std::vector<Value *> lhsexps;
                Obj lhss;
                stmt->obj("lhs",&lhss);
                emitTreeList(&lhss,false,&lhsexps);
                int N = lhsexps.size();
                for(int i = 0; i < N; i++)
                    B->CreateStore(rhsexps[i],lhsexps[i]);
            } break;
            case T_attrstore: {
                Obj addr,attr,value;
                stmt->obj("address",&addr);
                stmt->obj("attributes",&attr);
                stmt->obj("value",&value);
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
            } break;
            case T_apply: {
                Value * fnresult = emitCall(stmt);
                lua_pushlightuserdata(L, fnresult);
                stmt->setfield("returnvalue");
            } break;
            default: {
                emitExp(stmt,false);
            } break;
        }
    }
};

static int terra_codegen(lua_State * L) { //entry point into compiler from lua code
    terra_State * T = (terra_State*) lua_topointer(L,lua_upvalueindex(1));
    assert(T->L == L);
    
    //create lua table to hold object references anchored on stack
    int ref_table = lobj_newreftable(T->L);
    
    {
        TerraCompiler c;
        c.run(T,ref_table);
    } //scope to ensure that all Obj held in the compiler are destroyed before we pop the reference table off the stack
    
    lobj_removereftable(T->L,ref_table);
    
    return 0;
}


static int terra_createglobal(lua_State * L) { //entry point into compiler from lua code
    terra_State * T = (terra_State*) lua_topointer(L,lua_upvalueindex(1));
    assert(T->L == L);
    
    //create lua table to hold object references anchored on stack
    int ref_table = lobj_newreftable(T->L);
    
    {
        CCallingConv CC;
        CC.init(T, T->C, NULL);
        Obj global;
        lua_pushvalue(T->L,-2); //original argument
        global.initFromStack(T->L, ref_table);
        GetGlobalVariable(&CC,&global,"anon");
    } //scope to ensure that all Obj held in the compiler are destroyed before we pop the reference table off the stack
    
    lobj_removereftable(T->L,ref_table);
    
    return 0;
}

static int terra_optimize(lua_State * L) {
    terra_State * T = (terra_State*) lua_topointer(L,lua_upvalueindex(1));
    assert(T->L == L);
    
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
        DEBUG_ONLY(T) {
            printf("optimizing scc containing: ");
        }
        for(int i = 0; i < N; i++) {
            Obj funcobj;
            funclist.objAt(i,&funcobj);
            Function * func = (Function*) funcobj.ud("llvm_function");
            assert(func);
            scc.push_back(func);
            DEBUG_ONLY(T) {
                std::string s = func->getName();
                printf("%s ",s.c_str());
            }
        }
        DEBUG_ONLY(T) {
            printf("\n");
        }
        
        T->C->mi->runOnSCC(scc);
    
        for(int i = 0; i < N; i++) {
            Obj funcobj;
            funclist.objAt(i,&funcobj);
            Function * func = (Function*) funcobj.ud("llvm_function");
            assert(func);
            
            DEBUG_ONLY(T) {
                std::string s = func->getName();
                printf("optimizing %s\n",s.c_str());
            }
            double begin = CurrentTimeInSeconds();
            T->C->fpm->run(*func);
            RecordTime(&funcobj,"opt",begin);
            
            DEBUG_ONLY(T) {
                func->dump();
            }
        }
    } //scope to ensure that all Obj held in the compiler are destroyed before we pop the reference table off the stack
    
    lobj_removereftable(T->L,ref_table);
    
    return 0;
}

static int terra_jit(lua_State * L) {
    terra_State * T = (terra_State*) lua_topointer(L,lua_upvalueindex(1));
    assert(T->L == L);
    
    int ref_table = lobj_newreftable(T->L);
    
    {
        Obj jitobj, funcobj, flags;
        lua_pushvalue(L,-2); //original argument
        jitobj.initFromStack(L, ref_table);
        jitobj.obj("func", &funcobj);
        jitobj.obj("flags",&flags);
        Function * func = (Function*) funcobj.ud("llvm_function");
        assert(func);
        ExecutionEngine * ee = T->C->ee;
        
        if(flags.hasfield("usemcjit")) {
            //THIS IS AN ENOURMOUS HACK.
            //the execution engine will leak after this function
            //eventually llvm will fix MCJIT so it can handle Modules that add functions later
            //for now if we need it, we deal with the hacks...
            LLVMLinkInJIT();
            LLVMLinkInMCJIT();
            std::vector<std::string> attr;
            attr.push_back("+avx");
            std::string err;
            ee = EngineBuilder(T->C->m)
                 .setUseMCJIT(true)
                 .setMAttrs(attr)
                 .setErrorStr(&err)
                 .setEngineKind(EngineKind::JIT)
                 .create(T->C->tm);
            if (!ee) {
                printf("llvm: %s\n",err.c_str());
                abort();
            }
            ee->RegisterJITEventListener(T->C->jiteventlistener);

        }
        double begin = CurrentTimeInSeconds();
        void * ptr = ee->getPointerToFunction(func);
        RecordTime(&funcobj,"gen",begin);
        
        lua_pushlightuserdata(L, ptr);
        funcobj.setfield("fptr");
    } //scope to ensure that all Obj held in the compiler are destroyed before we pop the reference table off the stack
    
    lobj_removereftable(T->L,ref_table);
    
    return 0;
}

static int terra_deletefunction(lua_State * L) {
    terra_State * T = (terra_State*) lua_topointer(L,lua_upvalueindex(1));
    assert(T->L == L);
    Function ** fp = (Function**) lua_touserdata(L,-1);
    assert(fp);
    Function * func = (Function*) *fp;
    assert(func);
    DEBUG_ONLY(T) {
        printf("deleting function: %s\n",func->getName().str().c_str());
    }
    if(T->C->ee->getPointerToGlobalIfAvailable(func)) {
        DEBUG_ONLY(T) {
            printf("... and deleting generated code\n");
        }
        T->C->ee->freeMachineCodeForFunction(func); 
    }
    func->eraseFromParent();
    DEBUG_ONLY(T) {
        printf("... finish delete.\n");
    }
    *fp = NULL;
    return 0;
}
static int terra_disassemble(lua_State * L) {
    terra_State * T = (terra_State*) lua_topointer(L,lua_upvalueindex(1));
    assert(T->L == L);
    lua_getfield(L, -1, "fptr");
    void * data = lua_touserdata(L, -1);
    lua_getfield(L,-2,"llvm_function");
    Function * fn = (Function*) lua_touserdata(L, -1);
    assert(fn);
    fn->dump();
    size_t sz = T->C->functionsizes[fn];
    llvmutil_disassemblefunction(data, sz);
    return 0;
}

#ifndef _WIN32
static const char * GetTemporaryFile(char * tmpnamebuf, size_t len) {
    const char * tmp = "/tmp/terraXXXX.o";
    strcpy(tmpnamebuf, tmp);
    int fd = mkstemps(tmpnamebuf,2);
    close(fd);
    return tmpnamebuf;
} 
#else
static const char * GetTemporaryFile(char * tmpnamebuf, size_t len) {
    char firstbuf[256];
    DWORD tmpdirlen = GetTempPath(256, firstbuf);
    assert(tmpdirlen < 256-14);    // Enough space in the buffer to accomodate the tmp filename
    sprintf(&firstbuf[tmpdirlen], "terraXXXXXX");
    _mktemp(firstbuf);
    sprintf(tmpnamebuf, "%s.o", firstbuf);
    return tmpnamebuf;
}
#endif

static int terra_saveobjimpl(lua_State * L) {
    const char * filename = luaL_checkstring(L, -4);
    int tbl = lua_gettop(L) - 2;
    bool isexe = luaL_checkint(L, -2);
    terra_State * T = (terra_State*) lua_topointer(L,lua_upvalueindex(1));
    assert(T->L == L);
    int ref_table = lobj_newreftable(T->L);
    
    char tmpnamebuf[256];
    const char * objname = NULL;
    if(isexe) {
        objname = GetTemporaryFile(tmpnamebuf,256);
    } else {
        objname = filename;
    }
    
    {
        lua_pushvalue(L,-2);
        Obj arguments;
        arguments.initFromStack(L,ref_table);
    
        std::vector<Function *> livefns;
        std::vector<std::string> names;
        //iterate over the key value pairs in the table
        lua_pushnil(L);
        while (lua_next(L, tbl) != 0) {
            const char * key = luaL_checkstring(L, -2);
            Obj obj;
            obj.initFromStack(L, ref_table);
            Function * fnold = (Function*) obj.ud("llvm_function");
            assert(fnold);
            names.push_back(key);
            livefns.push_back(fnold);
        }
        
        Module * M = llvmutil_extractmodule(T->C->m, T->C->tm, &livefns, &names);
        
        DEBUG_ONLY(T) {
            printf("extraced module is:\n");
            M->dump();
        }
        
        //printf("saving %s\n",objname);
        std::string err = "";
        if(llvmutil_emitobjfile(M,T->C->tm,objname,&err)) {
            if(isexe)
                unlink(objname);
            delete M;
            terra_reporterror(T,"llvm: %s\n",err.c_str());
        }
        
        delete M;
        M = NULL;
        
        if(isexe) {
            sys::Path linker;
#ifndef _WIN32
            linker = sys::Program::FindProgramByName("gcc");
            if (linker.isEmpty()) {
                unlink(objname);
                terra_reporterror(T,"llvm: Failed to find gcc");
            }
#else
            linker = sys::Path(CLANG_EXECUTABLE);
#endif
            
            std::vector<const char *> args;
            args.push_back(linker.c_str());
            args.push_back(objname);
            args.push_back("-o");
            args.push_back(filename);
            
            int N = arguments.size();
            for(int i = 0; i < N; i++) {
                Obj arg;
                arguments.objAt(i,&arg);
                arg.push();
                args.push_back(luaL_checkstring(L,-1));
                lua_pop(L,1);
            }

            args.push_back(NULL);
            int c = sys::Program::ExecuteAndWait(linker, &args[0], 0, 0, 0, 0, &err);
            if(0 != c) {
                unlink(objname);
                terra_reporterror(T,"llvm: %s (%d)\n",err.c_str(),c);
            }
            unlink(objname);
        }
                
    }
    lobj_removereftable(T->L, ref_table);
    
    return 0;
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
    terra_State * T = (terra_State*) lua_topointer(L,lua_upvalueindex(1));
    assert(T->L == L);
    const char * filename = luaL_checkstring(L, -1);
    
    std::string Err;
    if(sys::DynamicLibrary::LoadLibraryPermanently(filename,&Err)) {
        terra_reporterror(T, "llvm: %s\n", Err.c_str());
    }
    
    return 0;
}

static int terra_dumpmodule(lua_State * L) {
    terra_State * T = (terra_State*) lua_topointer(L,lua_upvalueindex(1));
    assert(T->L == L);
    T->C->m->dump();
    return 0;
}



