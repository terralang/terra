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
#include <inttypes.h>

#include <cmath>
#include <sstream>
#include "llvmheaders.h"

#include "tcompilerstate.h"  //definition of terra_CompilerState which contains LLVM state
#include "tobj.h"
#if LLVM_VERSION < 170
// FIXME (Elliott): need to restore the manual inliner in LLVM 17
#include "tinline.h"
#endif
#include "llvm/Support/ManagedStatic.h"

#if LLVM_VERSION < 120
#include "llvm/ExecutionEngine/OrcMCJITReplacement.h"
#endif

#include "llvm/Support/Atomic.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/Path.h"
#include "tllvmutil.h"

#ifdef _WIN32
#include <io.h>
#include <time.h>
#include "twindows.h"
#undef interface
#else
#include <unistd.h>
#include <sys/time.h>
#endif

using namespace llvm;

#define TERRALIB_FUNCTIONS(_)                                                            \
    _(inittarget, 1)                                                                     \
    _(freetarget, 0)                                                                     \
    _(initcompilationunit, 1)                                                            \
    _(compilationunitaddvalue,                                                           \
      1) /*entry point from lua into compiler to generate LLVM for a function, other     \
            functions it calls may not yet exist*/                                       \
    _(freecompilationunit, 0)                                                            \
    _(jit, 1) /*entry point from lua into compiler to actually invoke the JIT by calling \
                 getPointerToFunction*/                                                  \
    _(llvmsizeof, 1)                                                                     \
    _(disassemble, 1)                                                                    \
    _(pointertolightuserdata, 0) /*because luajit ffi doesn't do this...*/               \
    _(bindtoluaapi, 0)                                                                   \
    _(gcdebug, 0)                                                                        \
    _(saveobjimpl, 1)                                                                    \
    _(linklibraryimpl, 1)                                                                \
    _(linkllvmimpl, 1)                                                                   \
    _(currenttimeinseconds, 0)                                                           \
    _(isintegral, 0)                                                                     \
    _(dumpmodule, 1)

#define DEF_LIBFUNCTION(nm, isclo) static int terra_##nm(lua_State *L);
TERRALIB_FUNCTIONS(DEF_LIBFUNCTION)
#undef DEF_LIBFUNCTION

#ifdef PRINT_LLVM_TIMING_STATS
static llvm_shutdown_obj llvmshutdownobj;
#endif

#define TERRA_DUMP_FUNCTION(t) (t)->print(llvm::errs(), nullptr)
#define TERRA_DUMP_TYPE(t) (t)->print(llvm::errs(), true)
#define TERRA_DUMP_MODULE(t) (t)->print(llvm::errs(), nullptr)

#define MEM_ARRAY_THRESHOLD 64

struct DisassembleFunctionListener : public JITEventListener {
    TerraCompilationUnit *CU;
    terra_State *T;
    DisassembleFunctionListener(TerraCompilationUnit *CU_) : CU(CU_), T(CU_->T) {}

    void InitializeDebugData(StringRef name, object::SymbolRef::Type type, uint64_t sz) {
        if (type == object::SymbolRef::ST_Function) {
#if !defined(__arm__) && !defined(__linux__) && !defined(__FreeBSD__)
            name = name.substr(1);
#endif
            void *addr = (void *)CU->ee->getFunctionAddress(name.str());
            if (addr) {
                assert(addr);
                TerraFunctionInfo &fi = T->C->functioninfo[addr];
                fi.ctx = CU->TT->ctx;
                fi.name = name.str();
                fi.addr = addr;
                fi.size = sz;
            }
        }
    }

    virtual void NotifyObjectEmitted(const object::ObjectFile &Obj,
                                     const RuntimeDyld::LoadedObjectInfo &L) {
        auto size_map = llvm::object::computeSymbolSizes(Obj);
        for (auto &S : size_map) {
            object::SymbolRef sym = S.first;
            auto name = sym.getName();
            auto type = sym.getType();
            if (name && type) InitializeDebugData(name.get(), type.get(), S.second);
        }
    }
};

class TerraSectionMemoryManager : public SectionMemoryManager {
public:
    TerraSectionMemoryManager(TerraCompilationUnit *CU_in, MemoryMapper *MM = nullptr)
            : SectionMemoryManager(MM) {
        CU = CU_in;
    }

    TerraSectionMemoryManager(const TerraSectionMemoryManager &) = delete;
    void operator=(const TerraSectionMemoryManager &) = delete;

    void notifyObjectLoaded(ExecutionEngine *EE, const object::ObjectFile &obj) override {
        auto size_map = llvm::object::computeSymbolSizes(obj);
        for (auto &S : size_map) {
            object::SymbolRef sym = S.first;
            auto name = sym.getName();
            auto type = sym.getType();
            // printf("notify: %s %d %#010llx\n", cantFail(std::move(name)).data(),
            // cantFail(std::move(type)), S.second);
            if (name && type)
                static_cast<DisassembleFunctionListener *>(CU->jiteventlistener)
                        ->InitializeDebugData(name.get(), type.get(), S.second);
        }
    }

private:
    TerraCompilationUnit *CU;
};

static double CurrentTimeInSeconds() {
#ifdef _WIN32
    static uint64_t freq = 0;
    if (freq == 0) {
        LARGE_INTEGER i;
        QueryPerformanceFrequency(&i);
        freq = i.QuadPart;
    }
    LARGE_INTEGER t;
    QueryPerformanceCounter(&t);
    return t.QuadPart / (double)freq;
#else
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec + tv.tv_usec / 1000000.0;
#endif
}
static int terra_currenttimeinseconds(lua_State *L) {
    lua_pushnumber(L, CurrentTimeInSeconds());
    return 1;
}

static void AddLLVMOptions(int N, ...) {
    va_list ap;
    va_start(ap, N);
    std::vector<const char *> ops;
    ops.push_back("terra");
    for (int i = 0; i < N; i++) {
        const char *arg = va_arg(ap, const char *);
        ops.push_back(arg);
    }
    cl::ParseCommandLineOptions(N + 1, &ops[0]);
}

// useful for debugging GC problems. You can attach it to
static int terra_gcdebug(lua_State *L) {
    lua_newuserdata(L, sizeof(void *));
    lua_getfield(L, LUA_GLOBALSINDEX, "terra");
    lua_getfield(L, -1, "llvm_gcdebugmetatable");
    lua_setmetatable(L, -3);
    lua_pop(L, 1);  // the 'terra' table
    lua_setfield(L, -2, "llvm_gcdebughandle");
    return 0;
}

static void RegisterFunction(struct terra_State *T, const char *name, int isclo,
                             lua_CFunction fn) {
    if (isclo) {
        lua_pushlightuserdata(T->L, (void *)T);
        lua_pushcclosure(T->L, fn, 1);
    } else {
        lua_pushcfunction(T->L, fn);
    }
    lua_setfield(T->L, -2, name);
}

static llvm::sys::Mutex terrainitlock;
static int terrainitcount;
bool OneTimeInit(struct terra_State *T) {
    bool success = true;
    terrainitlock.lock();
    terrainitcount++;
    if (terrainitcount == 1) {
#ifdef PRINT_LLVM_TIMING_STATS
        AddLLVMOptions(1, "-time-passes");
#endif
#if !defined(__arm__) && !defined(__aarch64__) && !defined(__PPC__)
        AddLLVMOptions(1, "-x86-asm-syntax=intel");
#endif
        InitializeAllTargets();
        InitializeAllTargetInfos();
        InitializeAllAsmPrinters();
        InitializeAllAsmParsers();
        InitializeAllTargetMCs();
    }
    terrainitlock.unlock();
    return success;
}

// LLVM 3.1 doesn't enable avx even if it is present, we detect and force it here
bool HostHasAVX() {
    StringMap<bool> Features;
    sys::getHostCPUFeatures(Features);
    return Features["avx"];
}

int terra_inittarget(lua_State *L) {
    terra_State *T = terra_getstate(L, 1);
    TerraTarget *TT = new TerraTarget();
    TT->id = T->targets.size();
    T->targets.push_back(TT);
    TT->nreferences = 2;

    if (!lua_isnil(L, 1)) {
        TT->Triple = lua_tostring(L, 1);
    } else {
        TT->Triple = llvm::sys::getProcessTriple();
    }
    if (!lua_isnil(L, 2))
        TT->CPU = lua_tostring(L, 2);
    else
        TT->CPU = llvm::sys::getHostCPUName().str();

#if defined(__x86_64__) || defined(_WIN32)
    if (TT->CPU == "generic") {
        TT->CPU = "x86-64";
    }
#endif

    if (!lua_isnil(L, 3))
        TT->Features = lua_tostring(L, 3);
    else {
#ifdef DISABLE_AVX
        TT->Features = "-avx";
#else
        TT->Features = HostHasAVX() ? "+avx" : "";
#endif
    }

    TargetOptions options;
    if (lua_toboolean(L, 4)) {  // FloatABIHard boolean
        options.FloatABIType = FloatABI::Hard;
    } else {
#ifdef __arm__
        // force hard float since we currently onlly work on platforms that have it
        options.FloatABIType = FloatABI::Hard;
#endif
    }

    TT->next_unused_id = 0;
    TT->ctx = new LLVMContext();
#if LLVM_VERSION >= 150 && LLVM_VERSION < 170
    // Hack: This is a workaround to avoid the opaque pointer
    // transition, but we will need to deal with it eventually.
    // FIXME: https://github.com/terralang/terra/issues/553
    TT->ctx->setOpaquePointers(false);
#endif
    std::string err;
    const Target *TheTarget = TargetRegistry::lookupTarget(TT->Triple, err);
    if (!TheTarget) {
        luaL_error(L, "failed to initialize target for LLVM Triple: %s (%s)",
                   TT->Triple.c_str(), err.c_str());
    }
    TT->tm = TheTarget->createTargetMachine(
            TT->Triple, TT->CPU, TT->Features, options,
#if defined(__linux__) || defined(__unix__)
            Reloc::PIC_,
#else
#if LLVM_VERSION < 160
            Optional<Reloc::Model>(),
#else
            std::optional<Reloc::Model>(),
#endif
#endif
#if defined(__powerpc64__)
            // On PPC the small model is limited to 16bit offsets
            CodeModel::Medium,
#else
            // Use small model so that we can use signed 32bits offset in the function and
            // GV tables
            CodeModel::Small,
#endif
            CodeGenOpt::Aggressive);
    TT->external = new Module("external", *TT->ctx);
    TT->external->setTargetTriple(TT->Triple);
    lua_pushlightuserdata(L, TT);
    return 1;
}

int terra_initcompilationunit(lua_State *L) {
    terra_State *T = terra_getstate(L, 1);
    TerraCompilationUnit *CU = new TerraCompilationUnit();
    TerraTarget *TT = (TerraTarget *)terra_tocdatapointer(L, 1);
    CU->TT = TT;
    CU->TT->nreferences++;
    CU->nreferences = 1;
    CU->T = T;
    CU->C = T->C;
    CU->C->nreferences++;
    CU->optimize = lua_toboolean(L, 2);

    int ref_table = lobj_newreftable(L);
    {
        Obj profile;
        lua_pushvalue(L, 3);
        profile.initFromStack(L, ref_table);
        assert(profile.hasfield("fastmath"));

        Obj mathflags;
        bool ok = profile.obj("fastmath", &mathflags);
        assert(ok);

        llvm::FastMathFlags fastmath;
        for (int i = 1; mathflags.hasfield(i); i++) {
            const char *flag = mathflags.string(i);
            // Thanks to LLVM's lack of support for parsing these values,
            // we have to do this by hand.
            if (strcmp(flag, "nnan") == 0) {
                fastmath.setNoNaNs();
            } else if (strcmp(flag, "ninf") == 0) {
                fastmath.setNoInfs();
            } else if (strcmp(flag, "nsz") == 0) {
                fastmath.setNoSignedZeros();
            } else if (strcmp(flag, "arcp") == 0) {
                fastmath.setAllowReciprocal();
            } else if (strcmp(flag, "contract") == 0) {
                fastmath.setAllowContract();
            } else if (strcmp(flag, "afn") == 0) {
                fastmath.setApproxFunc();
            } else if (strcmp(flag, "reassoc") == 0) {
                fastmath.setAllowReassoc();
            } else if (strcmp(flag, "fast") == 0) {
                fastmath.setFast();
            } else {
                assert(false && "unrecognized fast math flag");
            }
        }

        CU->fastmath = fastmath;
    }
    lobj_removereftable(L, ref_table);

    CU->M = new Module("terra", *TT->ctx);
    CU->M->setTargetTriple(TT->Triple);
    CU->M->setDataLayout(TT->tm->createDataLayout());

#if LLVM_VERSION < 170
    // FIXME (Elliott): need to restore the manual inliner in LLVM 17
    CU->mi = new ManualInliner(TT->tm, CU->M);
    CU->fpm = new FunctionPassManagerT(CU->M);
    llvmutil_addtargetspecificpasses(CU->fpm, TT->tm);
    llvmutil_addoptimizationpasses(CU->fpm);
    CU->fpm->doInitialization();
#else
    CU->fpm = new FunctionPassManager(llvmutil_createoptimizationpasses(
            TT->tm, CU->lam, CU->fam, CU->cgam, CU->mam));
#endif
    lua_pushlightuserdata(L, CU);
    return 1;
}

static void InitializeJIT(TerraCompilationUnit *CU) {
    if (CU->ee) return;  // already initialized
    Module *topeemodule = new Module("terra", *CU->TT->ctx);
#ifdef _WIN32
    std::string MCJITTriple = CU->TT->Triple;
    MCJITTriple.append("-elf");  // on windows we need to use an elf container because
                                 // coff is not supported yet
    topeemodule->setTargetTriple(MCJITTriple);
#else
    topeemodule->setTargetTriple(CU->TT->Triple);
#endif

    std::string err;
    std::vector<std::string> mattrs;
    if (!CU->TT->Features.empty()) mattrs.push_back(CU->TT->Features);
    EngineBuilder eb(UNIQUEIFY(Module, topeemodule));
    eb.setErrorStr(&err)
            .setMCPU(CU->TT->CPU)
            .setMAttrs(mattrs)
            .setEngineKind(EngineKind::JIT)
            .setTargetOptions(CU->TT->tm->Options)
            .setOptLevel(CodeGenOpt::Aggressive)
            .setMCJITMemoryManager(std::make_unique<TerraSectionMemoryManager>(CU))
#if LLVM_VERSION < 120
            .setUseOrcMCJITReplacement(true)
#endif
            ;

    CU->ee = eb.create();
    if (!CU->ee) terra_reporterror(CU->T, "llvm: %s\n", err.c_str());
    CU->jiteventlistener = new DisassembleFunctionListener(CU);
}

int terra_compilerinit(struct terra_State *T) {
    if (!OneTimeInit(T)) return LUA_ERRRUN;
    lua_getfield(T->L, LUA_GLOBALSINDEX, "terra");

#define REGISTER_FN(name, isclo) RegisterFunction(T, #name, isclo, terra_##name);
    TERRALIB_FUNCTIONS(REGISTER_FN)
#undef REGISTER_FN

    lua_pushnumber(T->L, LLVM_VERSION);
    lua_setfield(T->L, -2, "llvmversion");

    lua_pop(T->L, 1);  // remove terra from stack

    T->C = new terra_CompilerState();
    memset(T->C, 0, sizeof(terra_CompilerState));
    T->C->nreferences = 1;
    return 0;
}
void freetarget(TerraTarget *TT) {
    assert(TT->nreferences > 0);
    if (0 == --TT->nreferences) {
        delete TT->external;
        delete TT->tm;
        delete TT->ctx;
        delete TT;
    }
}
int terra_freetarget(lua_State *L) {
    freetarget((TerraTarget *)terra_tocdatapointer(L, 1));
    return 0;
}

static void freecompilationunit(TerraCompilationUnit *CU) {
    assert(CU->nreferences > 0);
    if (0 == --CU->nreferences) {
#if LLVM_VERSION < 170
        // FIXME (Elliott): need to restore the manual inliner in LLVM 17
        delete CU->mi;
#endif
        delete CU->fpm;
        if (CU->ee) {
            CU->ee->UnregisterJITEventListener(CU->jiteventlistener);
            delete CU->jiteventlistener;
            delete CU->ee;
        }
        delete CU->M;  // we own the module so we delete it
        freetarget(CU->TT);
        terra_compilerfree(CU->C);  // decrement reference count to compiler
        delete CU;
    }
}
int terra_freecompilationunit(lua_State *L) {
    freecompilationunit((TerraCompilationUnit *)terra_tocdatapointer(L, 1));
    return 0;
}

int terra_compilerfree(struct terra_CompilerState *C) {
    assert(C->nreferences > 0);
    if (0 == --C->nreferences) {
        if (C->MB.base() != NULL) {
            llvm::sys::Memory::releaseMappedMemory(C->MB);
        }
        C->functioninfo.clear();
        delete C;
    }
    return 0;
}

static void GetStructEntries(Obj *typ, Obj *entries) {
    Obj layout;
    if (!typ->obj("cachedlayout", &layout)) {
        assert(!"typechecked failed to complete type needed by the compiler, this is a bug.");
    }
    layout.obj("entries", entries);
}

struct TType {  // contains llvm raw type pointer and any metadata about it we need
    Type *type;
    bool issigned;
    bool islogical;
    bool incomplete;  // does this aggregate type or its children include an incomplete
                      // struct
};

class Types {
    TerraCompilationUnit *CU;
    terra_State *T;
    TType *GetIncomplete(Obj *typ) {
        TType *t = NULL;
        if (!LookupTypeCache(typ, &t)) {
            assert(t);
            switch (typ->kind("kind")) {
                case T_pointer: {
                    Obj base;
                    typ->obj("type", &base);
                    Type *baset = (base.kind("kind") == T_functype)
                                          ? Type::getInt8Ty(*CU->TT->ctx)
                                          : GetIncomplete(&base)->type;
                    t->type = PointerType::get(baset, typ->number("addressspace"));
                } break;
                case T_array: {
                    Obj base;
                    typ->obj("type", &base);
                    int N = typ->number("N");
                    TType *baset = GetIncomplete(&base);
                    t->type = ArrayType::get(baset->type, N);
                    t->incomplete = baset->incomplete;
                } break;
                case T_struct: {
                    StructType *st = CreateStruct(typ);
                    t->type = st;
                    t->incomplete = st->isOpaque();
                } break;
                case T_vector: {
                    Obj base;
                    typ->obj("type", &base);
                    int N = typ->number("N");
                    TType *ttype =
                            GetIncomplete(&base);  // vectors can only contain primitives,
                                                   // so the type must be complete
                    Type *baseType = ttype->type;
                    t->issigned = ttype->issigned;
                    t->islogical = ttype->islogical;
                    t->type = VectorType::get(baseType, N, false);
                } break;
                case T_primitive: {
                    CreatePrimitiveType(typ, t);
                } break;
                case T_niltype: {
                    t->type = Type::getInt8PtrTy(*CU->TT->ctx);
                } break;
                case T_opaque: {
                    t->type = Type::getInt8Ty(*CU->TT->ctx);
                } break;
                default: {
                    printf("kind = %d, %s\n", typ->kind("kind"),
                           tkindtostr(typ->kind("kind")));
                    terra_reporterror(T, "type not understood or not primitive\n");
                } break;
            }
        }
        assert(t && t->type);
        return t;
    }
    void CreatePrimitiveType(Obj *typ, TType *t) {
        int bytes = typ->number("bytes");
        switch (typ->kind("type")) {
            case T_float: {
                if (bytes == 4) {
                    t->type = Type::getFloatTy(*CU->TT->ctx);
                } else {
                    assert(bytes == 8);
                    t->type = Type::getDoubleTy(*CU->TT->ctx);
                }
            } break;
            case T_integer: {
                t->issigned = typ->boolean("signed");
                t->type = Type::getIntNTy(*CU->TT->ctx, bytes * 8);
            } break;
            case T_logical: {
                t->type = Type::getInt8Ty(*CU->TT->ctx);
                t->islogical = true;
            } break;
            default: {
                printf("kind = %d, %s\n", typ->kind("kind"),
                       tkindtostr(typ->kind("type")));
                terra_reporterror(T, "type not understood");
            } break;
        }
    }
    Type *FunctionPointerType() { return Type::getInt8PtrTy(*CU->TT->ctx); }
    bool LookupTypeCache(Obj *typ, TType **t) {
        *t = (TType *)CU->symbols->getud(typ);  // try to look up the cached type
        if (*t == NULL) {
            CU->symbols->push();
            typ->push();
            *t = (TType *)lua_newuserdata(T->L, sizeof(TType));
            lua_settable(T->L, -3);
            lua_pop(T->L, 1);
            memset(*t, 0, sizeof(TType));
            assert(*t != NULL);
            return false;
        }
        return true;
    }
    StructType *CreateStruct(Obj *typ) {
        // Note: historically, Terra tried to reuse the types generated by Clang when
        // importing C headers. This is why we maintain an `llvm_definingfunction` and
        // `llvm_definingtarget`. As of the opaque pointer migration (circa LLVM 15-17),
        // this approach no longer works. But it turns out that we don't need it: we can
        // just define the structs below, as we've always been doing (and found was
        // required for external targets).

        std::string name = typ->asstring("name");
        bool isreserved = beginsWith(name, "struct.") || beginsWith(name, "union.");
        name = (isreserved) ? std::string("$") + name : name;
        if (isreserved)
            return StructType::create(*CU->TT->ctx, name);
        else
            return StructType::create(*CU->TT->ctx);
    }
    bool beginsWith(const std::string &s, const std::string &prefix) {
        return s.substr(0, prefix.size()) == prefix;
    }
    void LayoutStruct(StructType *st, Obj *typ) {
        Obj layout;
        GetStructEntries(typ, &layout);
        int N = layout.size();
        std::vector<Type *> entry_types;

        MaybeAlign unionAlign;    // minimum union alignment
        Type *unionType = NULL;   // type with the largest alignment constraint
        size_t unionAlignSz = 0;  // size of type with largest alignment contraint
        size_t unionSz = 0;       // allocation size of the largest member

        for (int i = 0; i < N; i++) {
            Obj v;
            layout.objAt(i, &v);
            Obj vt;
            v.obj("type", &vt);

            Type *fieldtype = Get(&vt)->type;
            bool inunion = v.boolean("inunion");
            if (inunion) {
                Align align = CU->getDataLayout().getABITypeAlign(fieldtype);
                // orequal is to make sure we have a non-null
                // type even if it is a 0-sized struct
                if (encode(MaybeAlign(align)) >= encode(unionAlign)) {
                    unionAlign = align;
                    unionType = fieldtype;
                    unionAlignSz = CU->getDataLayout().getTypeAllocSize(fieldtype);
                }
                size_t allocSize = CU->getDataLayout().getTypeAllocSize(fieldtype);
                if (allocSize > unionSz) unionSz = allocSize;

                // check if this is the last member of the union, and if it is, add it to
                // our struct
                Obj nextObj;
                if (i + 1 < N) layout.objAt(i + 1, &nextObj);
                if (i + 1 == N ||
                    nextObj.number("allocation") != v.number("allocation")) {
                    std::vector<Type *> union_types;
                    assert(unionType);
                    union_types.push_back(unionType);
                    if (unionAlignSz <
                        unionSz) {  // the type with the largest alignment requirement is
                                    // not the type with the largest size, pad this struct
                                    // so that it will fit the largest type
                        size_t diff = unionSz - unionAlignSz;
                        union_types.push_back(
                                ArrayType::get(Type::getInt8Ty(*CU->TT->ctx), diff));
                    }
                    entry_types.push_back(StructType::get(*CU->TT->ctx, union_types));
                    unionAlign = MaybeAlign();
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
            TERRA_DUMP_TYPE(st);
            printf("\nEnd Layout\n");
        }
    }

public:
    Types(TerraCompilationUnit *CU_) : CU(CU_), T(CU_->T) {}
    TType *Get(Obj *typ) {
        assert(typ->kind("kind") != T_functype);  // Get should not be called on function
                                                  // directly, only function pointers
        TType *t = GetIncomplete(typ);
        if (t->incomplete) {
            assert(t->type->isAggregateType());
            switch (typ->kind("kind")) {
                case T_struct: {
                    LayoutStruct(cast<StructType>(t->type), typ);
                } break;
                case T_array: {
                    Obj base;
                    typ->obj("type", &base);
                    Get(&base);  // force base type to be completed
                } break;
                default:
                    terra_reporterror(
                            T, "type marked incomplete is not an array or struct\n");
            }
        }
        t->incomplete = false;
        return t;
    }
    bool IsUnitType(Obj *t) {
        t->pushfield("isunit");
        t->push();
        lua_call(T->L, 1, 1);
        bool result = lua_toboolean(T->L, -1);
        lua_pop(T->L, 1);
        return result;
    }
    void EnsureTypeIsComplete(Obj *typ) { Get(typ); }
    void EnsurePointsToCompleteType(Obj *ptrTy) {
        if (ptrTy->kind("kind") == T_pointer) {
            Obj objTy;
            ptrTy->obj("type", &objTy);
            EnsureTypeIsComplete(&objTy);
        }  // otherwise it is niltype and already complete
    }
    static void PointsToType(Obj *ptrTy, Obj *result) {
        if (ptrTy->kind("kind") == T_pointer) {
            ptrTy->obj("type", result);
        } else {
            printf("unexpected kind = %d, %s\n", ptrTy->kind("kind"),
                   tkindtostr(ptrTy->kind("kind")));
            assert(false);
        }
    }
};

// helper function to alloca at the beginning of function
static AllocaInst *CreateAlloca(IRBuilder<> *B, Type *Ty, Value *ArraySize = 0,
                                const Twine &Name = "") {
    BasicBlock *entry = &B->GetInsertBlock()->getParent()->getEntryBlock();
    IRBuilder<> TmpB(entry,
                     entry->begin());  // make sure alloca are at the beginning of the
                                       // function this is needed because alloca's that do
                                       // not dominate the function do weird things
    return TmpB.CreateAlloca(Ty, ArraySize, Name);
}

static Value *CreateConstGEP2_32(IRBuilder<> *B, Value *Ptr, Type *ValueType,
                                 unsigned Idx0, unsigned Idx1) {
    return B->CreateConstGEP2_32(ValueType, Ptr, Idx0, Idx1);
}

// functions that handle the details of the x86_64 ABI (this really should be handled by
// LLVM...)
struct CCallingConv {
    TerraCompilationUnit *CU;
    terra_State *T;
    lua_State *L;
    terra_CompilerState *C;
    Types *Ty;
    bool return_empty_struct_as_void;
    bool aarch64_cconv;
    bool amdgpu_cconv;
    bool ppc64_cconv;
    int ppc64_float_limit;
    int ppc64_int_limit;
    bool ppc64_count_used;
    bool spirv_cconv;
    bool wasm_cconv;

    CCallingConv(TerraCompilationUnit *CU_, Types *Ty_)
            : CU(CU_),
              T(CU_->T),
              L(CU_->T->L),
              C(CU_->T->C),
              Ty(Ty_),
              return_empty_struct_as_void(false),
              aarch64_cconv(false),
              amdgpu_cconv(false),
              ppc64_cconv(false),
              ppc64_float_limit(0),
              ppc64_int_limit(0),
              ppc64_count_used(false),
              spirv_cconv(false),
              wasm_cconv(false) {
        auto Triple = CU->TT->tm->getTargetTriple();
        switch (Triple.getArch()) {
            case Triple::ArchType::amdgcn: {
                return_empty_struct_as_void = true;
                amdgpu_cconv = true;
            } break;
            case Triple::ArchType::aarch64:
            case Triple::ArchType::aarch64_be: {
                aarch64_cconv = true;
                // Hack: we share code with the PPC64 cconv, so configure here.
                ppc64_float_limit = 4;
                ppc64_int_limit = 2;
                ppc64_count_used = false;
            } break;
            case Triple::ArchType::ppc64:
            case Triple::ArchType::ppc64le: {
                ppc64_cconv = true;
                ppc64_float_limit = 8;
                ppc64_int_limit = 8;
                ppc64_count_used = true;
            } break;
#if LLVM_VERSION >= 150
            case Triple::ArchType::spirv32:
            case Triple::ArchType::spirv64: {
                spirv_cconv = true;
            } break;
#endif
            case Triple::ArchType::wasm32:
            case Triple::ArchType::wasm64: {
                wasm_cconv = true;
            } break;
            default:
                break;
        }

        switch (Triple.getOS()) {
            case Triple::OSType::Win32: {
                return_empty_struct_as_void = true;
            } break;
            default:
                break;
        }
    }

    enum RegisterClass {
        C_NO_CLASS = 0,
        C_SSE_FLOAT = 1,
        C_SSE_DOUBLE = 2,
        C_INTEGER = 3,
        C_MEMORY = 4
    };

    enum ArgumentKind {
        C_PRIMITIVE,      // passed without modifcation (i.e. any non-aggregate type)
        C_AGGREGATE_REG,  // aggregate passed through registers
        C_AGGREGATE_MEM,  // aggregate passed through memory
        C_ARRAY_REG,      // aggregate passed through registers as an array
    };

    struct Argument {
        ArgumentKind kind;
        TType *type;   // orignal type for the object
        Type *cctype;  // if type == C_AGGREGATE_REG, this is a struct that holds a list
                       // of the values that goes into the registers
                       // if type == CC_PRIMITIVE, this is the struct that this type
                       // appear in the argument list and the type should be coerced to
        Argument() {}
        Argument(ArgumentKind kind, TType *type, Type *cctype = NULL) {
            this->kind = kind;
            this->type = type;
            this->cctype = cctype ? cctype : type->type;
        }
        int GetNumberOfTypesInParamList(Type *type) {
            StructType *st = dyn_cast<StructType>(type);
            if (st) {
                size_t total = 0;
                for (auto elt_type : st->elements()) {
                    total += GetNumberOfTypesInParamList(elt_type);
                }
                return total;
            }
            return 1;
        }
        int GetNumberOfTypesInParamList() {
            if (this->kind == C_AGGREGATE_REG)
                return GetNumberOfTypesInParamList(this->cctype);
            return 1;
        }
    };

    struct Classification {
        Argument returntype;
        std::vector<Argument> paramtypes;
        FunctionType *fntype;
    };

    RegisterClass Meet(RegisterClass a, RegisterClass b) { return (a > b) ? a : b; }

    void MergeValue(RegisterClass *classes, size_t offset, Obj *type) {
        Type *t = Ty->Get(type)->type;
        int entry = offset / 8;
        if (t->isVectorTy())  // we don't handle structures with vectors in them yet
            classes[entry] = C_MEMORY;
        else if (t->isFloatTy())
            classes[entry] = Meet(classes[entry], C_SSE_FLOAT);
        else if (t->isDoubleTy())
            classes[entry] = Meet(classes[entry], C_SSE_DOUBLE);
        else if (t->isIntegerTy() || t->isPointerTy())
            classes[entry] = Meet(classes[entry], C_INTEGER);
        else if (t->isStructTy()) {
            StructType *st = cast<StructType>(Ty->Get(type)->type);
            assert(!st->isOpaque());
            const StructLayout *sl = CU->getDataLayout().getStructLayout(st);
            Obj layout;
            GetStructEntries(type, &layout);
            int N = layout.size();
            for (int i = 0; i < N; i++) {
                Obj entry;
                layout.objAt(i, &entry);
                int allocation = entry.number("allocation");
                size_t structoffset = sl->getElementOffset(allocation);
                Obj entrytype;
                entry.obj("type", &entrytype);
                MergeValue(classes, offset + structoffset, &entrytype);
            }
        } else if (t->isArrayTy()) {
            ArrayType *at = cast<ArrayType>(Ty->Get(type)->type);
            size_t elemsize = CU->getDataLayout().getTypeAllocSize(at->getElementType());
            size_t sz = at->getNumElements();
            Obj elemtype;
            type->obj("type", &elemtype);
            for (size_t i = 0; i < sz; i++)
                MergeValue(classes, offset + i * elemsize, &elemtype);
        } else
            assert(!"unexpected value in classification");
    }
#ifndef _WIN32
    Type *TypeForClass(size_t size, RegisterClass clz) {
        switch (clz) {
            case C_SSE_FLOAT:
            case C_SSE_DOUBLE:
                switch (size) {
                    case 4:
                        return Type::getFloatTy(*CU->TT->ctx);
                    case 8:
                        return (C_SSE_DOUBLE == clz)
                                       ? Type::getDoubleTy(*CU->TT->ctx)
                                       : VectorType::get(Type::getFloatTy(*CU->TT->ctx),
                                                         2, false);
                    default:
                        assert(!"unexpected size for floating point class");
                }
            case C_INTEGER:
                assert(size <= 8);
                return Type::getIntNTy(*CU->TT->ctx, size * 8);
            default:
                assert(!"unexpected class");
        }
    }
    bool ValidAggregateSize(size_t sz) { return sz <= 16; }
#else
    Type *TypeForClass(size_t size, RegisterClass clz) {
        assert(size <= 8);
        return Type::getIntNTy(*CU->TT->ctx, size * 8);
    }
    bool ValidAggregateSize(size_t sz) {
        bool isPow2 = sz && !(sz & (sz - 1));
        return sz <= 8 && isPow2;
    }
#endif

    void CountValuesPPC64(Type *t, bool &all_float, bool &all_double, int &n_elts,
                          int64_t &align) {
        StructType *st = dyn_cast<StructType>(t);
        if (st) {
            for (auto elt : st->elements()) {
                CountValuesPPC64(elt, all_float, all_double, n_elts, align);
            }
            return;
        }

        ArrayType *at = dyn_cast<ArrayType>(t);
        if (at) {
            Type *elt = at->getElementType();
            uint64_t sz = at->getNumElements();
            for (uint64_t i = 0; i < sz; ++i) {
                CountValuesPPC64(elt, all_float, all_double, n_elts, align);
            }
            return;
        }

        all_float = all_float && t->isFloatTy();
        all_double = all_double && t->isDoubleTy();
        n_elts++;
        align = std::max(align,
                         (int64_t)(CU->getDataLayout().getABITypeAlign(t).value() * 8));
    }

    int WasmPrimitiveCount(Type *t) {
        if (t->isSingleValueType()) {
            return 1;
        }

        StructType *st = dyn_cast<StructType>(t);
        if (st) {
            int primCount = 0;
            for (auto elt : st->elements()) {
                primCount += WasmPrimitiveCount(elt);
            }
            return primCount;
        }

        // For the purpose of WASM calling conventions,
        // we say any array has 2 elements so it won't
        // be passed in registers
        return 2;
    }

    bool WasmIsSingletonOrEmpty(Type *t) { return WasmPrimitiveCount(t) <= 1; }

    void MergeValuePPC64(Type *t, std::vector<Type *> &elements, int64_t &bits) {
        StructType *st = dyn_cast<StructType>(t);
        if (st) {
            for (auto elt : st->elements()) {
                MergeValuePPC64(elt, elements, bits);
            }
            return;
        }

        ArrayType *at = dyn_cast<ArrayType>(t);
        if (at) {
            Type *elt = at->getElementType();
            uint64_t sz = at->getNumElements();
            for (uint64_t i = 0; i < sz; ++i) {
                MergeValuePPC64(elt, elements, bits);
            }
            return;
        }

        unsigned b = CU->getDataLayout().getTypeAllocSizeInBits(t);
        int64_t align = CU->getDataLayout().getABITypeAlign(t).value() * 8;
        bits += b;
        bits = (bits + align - 1) & (-align);  // Align to this type.
        if (bits >= 64) {
            elements.push_back(Type::getIntNTy(*CU->TT->ctx, 64));
            bits -= 64;
        }
    }

    Argument ClassifyAggPPC64(TType *t, int *usedint, bool isreturn) {
        bool all_float = true;
        bool all_double = true;
        int n_elts = 0;
        int64_t align = 0;
        CountValuesPPC64(t->type, all_float, all_double, n_elts, align);

        // Special cases: all-float or all-double up to N values via registers:
        if (all_float && n_elts > 0 && n_elts <= ppc64_float_limit) {
            *usedint += n_elts;
            if (n_elts == 1) {
                return Argument(C_AGGREGATE_REG, t,
                                StructType::get(Type::getFloatTy(*CU->TT->ctx)));
            } else {
                auto at = ArrayType::get(Type::getFloatTy(*CU->TT->ctx), n_elts);
                return Argument(C_ARRAY_REG, t, at);
            }
        }
        if (all_double && n_elts > 0 && n_elts <= ppc64_float_limit) {
            *usedint += n_elts;
            if (n_elts == 1) {
                return Argument(C_AGGREGATE_REG, t,
                                StructType::get(Type::getDoubleTy(*CU->TT->ctx)));
            } else {
                auto at = ArrayType::get(Type::getDoubleTy(*CU->TT->ctx), n_elts);
                return Argument(C_ARRAY_REG, t, at);
            }
        }

        // Integer or mixed case:

        // Can pack up to N registers, or 2 if this is a return. (A register is 64
        // bits or 8 bytes.)
        int sz = (CU->getDataLayout().getTypeAllocSize(t->type) + 7) / 8;
        int limit = isreturn ? 2 : ppc64_int_limit;
        if ((ppc64_count_used ? *usedint : 0) + sz <= limit) {
            *usedint += sz;

            // Pack arguments
            std::vector<Type *> elements;
            int64_t bits = 0;
            MergeValuePPC64(t->type, elements, bits);
            if (bits > 0) {
                // Align to the biggest type we've seen.
                elements.push_back(
                        Type::getIntNTy(*CU->TT->ctx, (bits + align - 1) & (-align)));
            }
            return Argument(C_AGGREGATE_REG, t, StructType::get(*CU->TT->ctx, elements));
        }
        return Argument(C_AGGREGATE_MEM, t);
    }

    Argument ClassifyArgument(Obj *type, int *usedfloat, int *usedint, bool isreturn) {
        TType *t = Ty->Get(type);

        if (!t->type->isAggregateType()) {
            if (t->type->isFloatingPointTy() || t->type->isVectorTy())
                ++*usedfloat;
            else
                ++*usedint;
            bool usei1 = t->islogical && !t->type->isVectorTy();
            return Argument(C_PRIMITIVE, t, usei1 ? Type::getInt1Ty(*CU->TT->ctx) : NULL);
        }

        if ((wasm_cconv && !WasmIsSingletonOrEmpty(t->type)) || spirv_cconv) {
            return Argument(C_AGGREGATE_MEM, t);
        }

        if (amdgpu_cconv) {
            return Argument(C_AGGREGATE_REG, t, t->type);
        }

        if (aarch64_cconv || ppc64_cconv) {
            return ClassifyAggPPC64(t, usedint, isreturn);
        }

        int sz = CU->getDataLayout().getTypeAllocSize(t->type);
        if (!ValidAggregateSize(sz)) {
            return Argument(C_AGGREGATE_MEM, t);
        }

        RegisterClass classes[] = {C_NO_CLASS, C_NO_CLASS};

        int sizes[] = {std::min(sz, 8), std::max(0, sz - 8)};
        MergeValue(classes, 0, type);
        if (classes[0] == C_MEMORY || classes[1] == C_MEMORY) {
            return Argument(C_AGGREGATE_MEM, t);
        }
        int nfloat = (classes[0] == C_SSE_FLOAT || classes[0] == C_SSE_DOUBLE) +
                     (classes[1] == C_SSE_FLOAT || classes[1] == C_SSE_DOUBLE);
        int nint = (classes[0] == C_INTEGER) + (classes[1] == C_INTEGER);
        if (sz > 8 && (*usedfloat + nfloat > 8 || *usedint + nint > 6)) {
            return Argument(C_AGGREGATE_MEM, t);
        }

        *usedfloat += nfloat;
        *usedint += nint;

        std::vector<Type *> elements;
        for (int i = 0; i < 2; i++)
            if (sizes[i] > 0) elements.push_back(TypeForClass(sizes[i], classes[i]));

        return Argument(C_AGGREGATE_REG, t, StructType::get(*CU->TT->ctx, elements));
    }
    void Classify(Obj *ftype, CallingConv::ID cconv, Obj *params, Classification *info) {
        Obj fparams, returntype;
        ftype->obj("parameters", &fparams);
        ftype->obj("returntype", &returntype);
        int zero = 0;
        info->returntype = ClassifyArgument(&returntype, &zero, &zero, true);

        if (return_empty_struct_as_void || cconv == CallingConv::SPIR_KERNEL) {
            // windows classifies empty structs as pass by pointer, but we need a return
            // value of unit (an empty tuple) to be translated to void. So if it is unit,
            // force the return value to be void by overriding the normal classification
            // decision
            if (Ty->IsUnitType(&returntype)) {
                info->returntype = Argument(C_AGGREGATE_REG, info->returntype.type,
                                            StructType::get(*CU->TT->ctx));
            }
        }

        int nfloat = 0;
        int nint = info->returntype.kind == C_AGGREGATE_MEM
                           ? 1
                           : 0; /*sret consumes RDI for the return value pointer so it
                                   counts towards the used integer registers*/
        int N = params->size();
        for (int i = 0; i < N; i++) {
            Obj elem;
            params->objAt(i, &elem);
            info->paramtypes.push_back(ClassifyArgument(&elem, &nfloat, &nint, false));
        }
        info->fntype =
                CreateFunctionType(info, fparams.size(), ftype->boolean("isvararg"));
    }

    Classification *ClassifyFunction(Obj *fntyp, CallingConv::ID cconv) {
        Classification *info = (Classification *)CU->symbols->getud(fntyp);
        if (!info) {
            info = new Classification();  // TODO: fix leak
            Obj params;
            fntyp->obj("parameters", &params);
            Classify(fntyp, cconv, &params, info);
            CU->symbols->setud(fntyp, info);
        }
        return info;
    }

    template <typename FnOrCall>
    void addSRetAttr(FnOrCall *r, int idx, Type *ty) {
#if LLVM_VERSION < 120
        r->addParamAttr(idx - 1, Attribute::StructRet);
#else
        r->addParamAttr(idx - 1, Attribute::getWithStructRetType(*CU->TT->ctx, ty));
#endif
        r->addParamAttr(idx - 1, Attribute::NoAlias);
    }
    template <typename FnOrCall>
    void addByValAttr(FnOrCall *r, int idx, Type *ty) {
#if LLVM_VERSION < 120
        r->addParamAttr(idx - 1, Attribute::ByVal);
#else
        r->addParamAttr(idx - 1, Attribute::getWithByValType(*CU->TT->ctx, ty));
#endif
    }
    template <typename FnOrCall>
    void addNoUndefAttr(FnOrCall *r, int idx) {
        r->addParamAttr(idx - 1, Attribute::NoUndef);
    }
    template <typename FnOrCall>
    void addExtAttrIfNeeded(TType *t, FnOrCall *r, int idx, bool return_value = false) {
        if (!t->type->isIntegerTy() || t->type->getPrimitiveSizeInBits() >= 32) return;
        if (return_value) {
            if (!aarch64_cconv) {
#if LLVM_VERSION < 140
                assert(idx == 0);
                r->addAttribute(0, t->issigned ? Attribute::SExt : Attribute::ZExt);
#else
                r->addRetAttr(t->issigned ? Attribute::SExt : Attribute::ZExt);
#endif
            }
        } else {
            r->addParamAttr(idx - 1, t->issigned ? Attribute::SExt : Attribute::ZExt);
        }
    }

    template <typename FnOrCall>
    void AttributeFnOrCall(FnOrCall *r, Classification *info) {
        addExtAttrIfNeeded(info->returntype.type, r, 0, true);
        int argidx = 1;
        if (info->returntype.kind == C_AGGREGATE_MEM) {
            addSRetAttr(r, argidx, info->returntype.cctype);
            argidx++;
        }
        for (size_t i = 0; i < info->paramtypes.size(); i++) {
            Argument *v = &info->paramtypes[i];
            if (v->kind == C_AGGREGATE_MEM) {
#ifndef _WIN32
                if (!aarch64_cconv) {
                    addByValAttr(r, argidx, v->cctype);
                } else {
                    addNoUndefAttr(r, argidx);
                }
#endif
            }
            addExtAttrIfNeeded(v->type, r, argidx);
            argidx += v->GetNumberOfTypesInParamList();
        }
    }

    Value *emitStoreAgg(IRBuilder<> *B, Type *t1, Value *src, Value *addr_dst) {
        assert(t1->isAggregateType());
        LoadInst *l = dyn_cast<LoadInst>(src);
        if ((t1->isStructTy() || (t1->isArrayTy())) && l) {
            Value *addr_src = l->getOperand(0);
#if LLVM_VERSION < 170
            // create bitcasts of src and dest address
            unsigned as_src = addr_src->getType()->getPointerAddressSpace();
            Type *t_src = Type::getInt8PtrTy(*CU->TT->ctx, as_src);
            unsigned as_dst = addr_dst->getType()->getPointerAddressSpace();
            Type *t_dst = Type::getInt8PtrTy(*CU->TT->ctx, as_dst);
            Value *addr_dest = B->CreateBitCast(addr_dst, t_dst);
            Value *addr_source = B->CreateBitCast(addr_src, t_src);
#else
            Value *addr_dest = addr_dst;
            Value *addr_source = addr_src;
#endif
            uint64_t size = 0;
            MaybeAlign a1;
            if (t1->isStructTy()) {
                // size of bytes to copy
                StructType *st = cast<StructType>(t1);
                const StructLayout *sl = CU->getDataLayout().getStructLayout(st);
                size = sl->getSizeInBytes();
                a1 = sl->getAlignment();
            } else if (t1->isArrayTy()) {
                size = CU->getDataLayout().getTypeAllocSize(t1);
                if (size < MEM_ARRAY_THRESHOLD) {
                    StoreInst *st = B->CreateStore(src, addr_dst);
                    return st;
                }
                a1 = MaybeAlign(CU->getDataLayout().getABITypeAlign(t1));
            } else
                assert(!"unhandled type in emitStoreAgg");
            Value *size_v = ConstantInt::get(Type::getInt64Ty(*CU->TT->ctx), size);
            // perform the copy
            Value *m = B->CreateMemCpy(addr_dest, a1, addr_source, a1, size_v);
            return m;
        } else {
            StoreInst *st = B->CreateStore(src, addr_dst);
            return st;
        }
    }

    Function *CreateFunction(Module *M, Obj *ftype, CallingConv::ID cconv,
                             const Twine &name) {
        Classification *info = ClassifyFunction(ftype, cconv);
        Function *fn = Function::Create(info->fntype, Function::InternalLinkage, name, M);
        AttributeFnOrCall(fn, info);
        return fn;
    }

    PointerType *Ptr(Type *t, unsigned as = 0) { return PointerType::get(t, as); }
    Value *ConvertPrimitive(IRBuilder<> *B, Value *src, Type *dstType, bool issigned) {
        if (!dstType->isIntegerTy()) return src;
        if (dstType == Type::getInt1Ty(*CU->TT->ctx)) {
            return B->CreateICmpNE(src, ConstantInt::get(src->getType(), 0));
        } else {
            return B->CreateIntCast(src, dstType, issigned);
        }
    }
    void EmitEntryAggReg(IRBuilder<> *B, Value *dest, Type *arg_type,
                         Function::arg_iterator &ai) {
        StructType *st = dyn_cast<StructType>(arg_type);
        if (st) {
            int N = st->getNumElements();
            for (int j = 0; j < N; j++) {
                Type *elt_type = st->getElementType(j);
                EmitEntryAggReg(B, CreateConstGEP2_32(B, dest, st, 0, j), elt_type, ai);
            }
        } else {
            B->CreateStore(&*ai, dest);
            ++ai;
        }
    }
    void EmitEntry(IRBuilder<> *B, Obj *ftype, Function *func,
                   std::vector<Value *> *variables) {
        Classification *info = ClassifyFunction(ftype, func->getCallingConv());
        assert(info->paramtypes.size() == variables->size());
        Function::arg_iterator ai = func->arg_begin();
        if (info->returntype.kind == C_AGGREGATE_MEM)
            ++ai;  // first argument is the return structure, skip it when loading
                   // arguments
        for (size_t i = 0; i < variables->size(); i++) {
            Argument *p = &info->paramtypes[i];
            Value *v = (*variables)[i];
            switch (p->kind) {
                case C_PRIMITIVE: {
                    Value *a =
                            ConvertPrimitive(B, &*ai, p->type->type, p->type->issigned);
                    B->CreateStore(a, v);
                    ++ai;
                } break;
                case C_AGGREGATE_MEM:
                    // TODO: check that LLVM optimizes this copy away
                    emitStoreAgg(B, p->type->type, B->CreateLoad(p->type->type, &*ai), v);
                    ++ai;
                    break;
                case C_AGGREGATE_REG: {
#if LLVM_VERSION < 170
                    unsigned as = v->getType()->getPointerAddressSpace();
                    Value *dest = B->CreateBitCast(v, Ptr(p->cctype, as));
                    EmitEntryAggReg(B, dest, p->cctype, ai);
#else
                    EmitEntryAggReg(B, v, p->cctype, ai);
#endif
                } break;
                case C_ARRAY_REG: {
                    Value *scratch = CreateAlloca(B, p->cctype);
                    emitStoreAgg(B, p->cctype, &*ai, scratch);
#if LLVM_VERSION < 170
                    unsigned as = scratch->getType()->getPointerAddressSpace();
                    Value *casted = B->CreateBitCast(scratch, Ptr(p->type->type, as));
                    emitStoreAgg(B, p->type->type, B->CreateLoad(p->type->type, casted),
                                 v);
#else
                    emitStoreAgg(B, p->type->type, B->CreateLoad(p->type->type, scratch),
                                 v);
#endif
                    ++ai;
                } break;
            }
        }
    }
    void EmitReturn(IRBuilder<> *B, Obj *ftype, Function *function, Value *result) {
        Classification *info = ClassifyFunction(ftype, function->getCallingConv());
        ArgumentKind kind = info->returntype.kind;

        if (C_AGGREGATE_REG == kind &&
            info->returntype.GetNumberOfTypesInParamList() == 0) {
            B->CreateRetVoid();
        } else if (C_PRIMITIVE == kind) {
            B->CreateRet(ConvertPrimitive(B, result, info->returntype.cctype,
                                          info->returntype.type->issigned));
        } else if (C_AGGREGATE_MEM == kind) {
            emitStoreAgg(B, info->returntype.type->type, result, &*function->arg_begin());
            B->CreateRetVoid();
        } else if (C_AGGREGATE_REG == kind) {
            Value *dest = CreateAlloca(B, info->returntype.type->type);
            emitStoreAgg(B, info->returntype.type->type, result, dest);
            StructType *type = cast<StructType>(info->returntype.cctype);
#if LLVM_VERSION < 170
            unsigned as = dest->getType()->getPointerAddressSpace();
            Value *result = B->CreateBitCast(dest, Ptr(type, as));
#else
            Value *result = dest;
#endif
            Type *result_type = type;
            if (info->returntype.GetNumberOfTypesInParamList() == 1) {
                do {
                    result = CreateConstGEP2_32(B, result, type, 0, 0);
                    result_type = type->getElementType(0);
                } while ((type = dyn_cast<StructType>(result_type)));
            }
            B->CreateRet(B->CreateLoad(result_type, result));
        } else if (C_ARRAY_REG == kind) {
            Value *dest = CreateAlloca(B, info->returntype.type->type);
            emitStoreAgg(B, info->returntype.type->type, result, dest);
            ArrayType *result_type = cast<ArrayType>(info->returntype.cctype);
#if LLVM_VERSION < 170
            unsigned as = dest->getType()->getPointerAddressSpace();
            Value *result = B->CreateBitCast(dest, Ptr(result_type, as));
#else
            Value *result = dest;
#endif
            B->CreateRet(B->CreateLoad(result_type, result));
        } else {
            assert(!"unhandled return value");
        }
    }

    void EmitCallAggReg(IRBuilder<> *B, Value *value, Type *param_type,
                        std::vector<Value *> &arguments) {
        StructType *st = dyn_cast<StructType>(param_type);
        if (st) {
            int N = st->getNumElements();
            for (int j = 0; j < N; j++) {
                Type *elt_type = st->getElementType(j);
                EmitCallAggReg(B, CreateConstGEP2_32(B, value, st, 0, j), elt_type,
                               arguments);
            }
        } else {
            arguments.push_back(B->CreateLoad(param_type, value));
        }
    }

    Value *EmitCall(IRBuilder<> *B, Obj *ftype, CallingConv::ID cconv, Obj *paramtypes,
                    Value *callee, std::vector<Value *> *actuals) {
        Classification info;
        Classify(ftype, cconv, paramtypes, &info);

        std::vector<Value *> arguments;

        if (C_AGGREGATE_MEM == info.returntype.kind) {
            arguments.push_back(CreateAlloca(B, info.returntype.type->type));
        }

        for (size_t i = 0; i < info.paramtypes.size(); i++) {
            Argument *a = &info.paramtypes[i];
            Value *actual = (*actuals)[i];
            switch (a->kind) {
                case C_PRIMITIVE:
                    arguments.push_back(
                            ConvertPrimitive(B, actual, a->cctype, a->type->issigned));
                    break;
                case C_AGGREGATE_MEM: {
                    Value *scratch = CreateAlloca(B, a->type->type);
                    emitStoreAgg(B, a->type->type, actual, scratch);
                    arguments.push_back(scratch);
                } break;
                case C_AGGREGATE_REG: {
                    Value *scratch = CreateAlloca(B, a->type->type);
                    emitStoreAgg(B, a->type->type, actual, scratch);
#if LLVM_VERSION < 170
                    unsigned as = scratch->getType()->getPointerAddressSpace();
                    Value *casted = B->CreateBitCast(scratch, Ptr(a->cctype, as));
                    EmitCallAggReg(B, casted, a->cctype, arguments);
#else
                    EmitCallAggReg(B, scratch, a->cctype, arguments);
#endif
                } break;
                case C_ARRAY_REG: {
                    Value *scratch = CreateAlloca(B, a->type->type);
                    emitStoreAgg(B, a->type->type, actual, scratch);
#if LLVM_VERSION < 170
                    unsigned as = scratch->getType()->getPointerAddressSpace();
                    Value *casted = B->CreateBitCast(scratch, Ptr(a->cctype, as));
                    EmitCallAggReg(B, casted, a->cctype, arguments);
#else
                    EmitCallAggReg(B, scratch, a->cctype, arguments);
#endif
                } break;
                default: {
                    assert(!"unhandled argument kind");
                } break;
            }
        }

        // emit call
#if LLVM_VERSION < 170
        // function pointers are stored as &int8 to avoid calling convension issues
        // cast it back to the real pointer type right before calling it
        callee = B->CreateBitCast(callee, Ptr(info.fntype));
#else
        assert(callee->getType()->isPointerTy());
#endif
        CallInst *call = B->CreateCall(info.fntype, callee, arguments);
        // annotate call with byval and sret
        AttributeFnOrCall(call, &info);

        // unstage results
        if (C_PRIMITIVE == info.returntype.kind) {
            return ConvertPrimitive(B, call, info.returntype.type->type,
                                    info.returntype.type->issigned);
        } else {
            Value *aggregate;
            if (C_AGGREGATE_MEM == info.returntype.kind) {
                aggregate = arguments[0];
            } else if (C_AGGREGATE_REG == info.returntype.kind) {
                aggregate = CreateAlloca(B, info.returntype.type->type);
                StructType *type = cast<StructType>(info.returntype.cctype);
#if LLVM_VERSION < 170
                unsigned as = aggregate->getType()->getPointerAddressSpace();
                Value *casted = B->CreateBitCast(aggregate, Ptr(type, as));
#else
                Value *casted = aggregate;
#endif
                if (info.returntype.GetNumberOfTypesInParamList() == 1) {
                    do {
                        casted = CreateConstGEP2_32(B, casted, type, 0, 0);
                    } while ((type = dyn_cast<StructType>(type->getElementType(0))));
                }
                if (info.returntype.GetNumberOfTypesInParamList() > 0)
                    B->CreateStore(call, casted);
            } else if (C_ARRAY_REG == info.returntype.kind) {
                aggregate = CreateAlloca(B, info.returntype.type->type);
                ArrayType *type = cast<ArrayType>(info.returntype.cctype);
#if LLVM_VERSION < 170
                unsigned as = aggregate->getType()->getPointerAddressSpace();
                Value *casted = B->CreateBitCast(aggregate, Ptr(type, as));
                emitStoreAgg(B, type, call, casted);
#else
                emitStoreAgg(B, type, call, aggregate);
#endif
            } else {
                assert(!"unhandled argument kind");
            }
            return B->CreateLoad(info.returntype.type->type, aggregate);
        }
    }
    void GatherArgumentsAggReg(Type *type, std::vector<Type *> &arguments) {
        StructType *st = dyn_cast<StructType>(type);
        if (st) {
            for (auto elt_type : st->elements()) {
                GatherArgumentsAggReg(elt_type, arguments);
            }
        } else {
            arguments.push_back(type);
        }
    }
    FunctionType *CreateFunctionType(Classification *info, int formal_params,
                                     bool isvararg) {
        std::vector<Type *> arguments;

        Type *rt = NULL;
        switch (info->returntype.kind) {
            case C_AGGREGATE_REG: {
                switch (info->returntype.GetNumberOfTypesInParamList()) {
                    case 0:
                        rt = Type::getVoidTy(*CU->TT->ctx);
                        break;
                    case 1: {
                        StructType *type = cast<StructType>(info->returntype.cctype);
                        do {
                            rt = type->getElementType(0);
                        } while ((type = dyn_cast<StructType>(rt)));
                    } break;
                    default:
                        rt = info->returntype.cctype;
                        break;
                }
            } break;
            case C_AGGREGATE_MEM: {
                rt = Type::getVoidTy(*CU->TT->ctx);
                arguments.push_back(Ptr(info->returntype.type->type));
            } break;
            case C_ARRAY_REG: {
                rt = info->returntype.cctype;
            } break;
            case C_PRIMITIVE: {
                rt = info->returntype.cctype;
            } break;
            default: {
                assert(!"unhandled argument kind");
            } break;
        }
        if (isvararg) {
            assert(formal_params <= info->paramtypes.size());
        } else {
            assert(formal_params == info->paramtypes.size());
        }
        for (size_t i = 0; i < formal_params; i++) {
            Argument *a = &info->paramtypes[i];
            switch (a->kind) {
                case C_PRIMITIVE: {
                    arguments.push_back(a->cctype);
                } break;
                case C_AGGREGATE_MEM:
                    arguments.push_back(Ptr(a->type->type));
                    break;
                case C_AGGREGATE_REG: {
                    GatherArgumentsAggReg(a->cctype, arguments);
                } break;
                case C_ARRAY_REG: {
                    arguments.push_back(a->cctype);
                } break;
                default: {
                    assert(!"unhandled argument kind");
                } break;
            }
        }

        return FunctionType::get(rt, arguments, isvararg);
    }
};

static Constant *EmitConstantInitializer(TerraCompilationUnit *CU, Obj *v);

static GlobalVariable *CreateGlobalVariable(TerraCompilationUnit *CU, Obj *global,
                                            const char *name) {
    Obj t;
    global->obj("type", &t);
    Type *typ = CU->Ty->Get(&t)->type;

    Constant *llvmconstant = global->boolean("extern") ? NULL : UndefValue::get(typ);
    Obj constant;
    if (global->obj("initializer", &constant)) {
        llvmconstant = EmitConstantInitializer(CU, &constant);
    }
    int as = global->number("addressspace");
    GlobalValue::LinkageTypes linkage =
            (global->boolean("constant") && !global->boolean("extern"))
                    ? GlobalValue::InternalLinkage
                    : GlobalValue::ExternalLinkage;
    return new GlobalVariable(*CU->M, typ, global->boolean("constant"), linkage,
                              llvmconstant, name, NULL, GlobalVariable::NotThreadLocal,
                              as);
}

static bool AlwaysShouldCopy(GlobalValue *G, void *data) { return true; }

static GlobalVariable *EmitGlobalVariable(TerraCompilationUnit *CU, Obj *global,
                                          const char *name) {
    GlobalVariable *gv = (GlobalVariable *)CU->symbols->getud(global);
    if (gv == NULL) {
        if (global->hasfield("name"))
            name = global->string("name");  // globals given name overrides the alternate
                                            // name given when the global is created
        if (global->boolean("extern")) {
            gv = CU->M->getGlobalVariable(name);
            if (!gv) {
                GlobalValue *externglobal = CU->TT->external->getGlobalVariable(name);
                if (externglobal) {
                    llvmutil_copyfrommodule(CU->M, CU->TT->external, &externglobal, 1,
                                            AlwaysShouldCopy, NULL);
                    gv = CU->M->getGlobalVariable(name);
                    assert(gv);
                }
            }
        }
        if (!gv) gv = CreateGlobalVariable(CU, global, name);
        CU->symbols->setud(global, gv);
    }
    return gv;
}

static CallingConv::ID ParseCallingConv(const char *cc) {
    // LLVM does not provide a way to parse this programmatically, so
    // we're just going to replicate the table from llvm/lib/IR/AsmWriter.cpp
    static std::map<std::string, CallingConv::ID> ccmap;
    static bool init = false;
    if (!init) {
        init = true;
        ccmap["fastcc"] = CallingConv::Fast;
        ccmap["coldcc"] = CallingConv::Cold;
        ccmap["webkit_jscc"] = CallingConv::WebKit_JS;
        ccmap["anyregcc"] = CallingConv::AnyReg;
        ccmap["preserve_mostcc"] = CallingConv::PreserveMost;
        ccmap["preserve_allcc"] = CallingConv::PreserveAll;
        ccmap["cxx_fast_tlscc"] = CallingConv::CXX_FAST_TLS;
        ccmap["ghccc"] = CallingConv::GHC;
        ccmap["tailcc"] = CallingConv::Tail;
        ccmap["cfguard_checkcc"] = CallingConv::CFGuard_Check;
        ccmap["x86_stdcallcc"] = CallingConv::X86_StdCall;
        ccmap["x86_fastcallcc"] = CallingConv::X86_FastCall;
        ccmap["x86_thiscallcc"] = CallingConv::X86_ThisCall;
        ccmap["x86_regcallcc"] = CallingConv::X86_RegCall;
        ccmap["x86_vectorcallcc"] = CallingConv::X86_VectorCall;
        ccmap["intel_ocl_bicc"] = CallingConv::Intel_OCL_BI;
        ccmap["arm_apcscc"] = CallingConv::ARM_APCS;
        ccmap["arm_aapcscc"] = CallingConv::ARM_AAPCS;
        ccmap["arm_aapcs_vfpcc"] = CallingConv::ARM_AAPCS_VFP;
        ccmap["aarch64_vector_pcs"] = CallingConv::AArch64_VectorCall;
        ccmap["aarch64_sve_vector_pcs"] = CallingConv::AArch64_SVE_VectorCall;
        ccmap["msp430_intrcc"] = CallingConv::MSP430_INTR;
        ccmap["avr_intrcc"] = CallingConv::AVR_INTR;
        ccmap["avr_signalcc"] = CallingConv::AVR_SIGNAL;
        ccmap["ptx_kernel"] = CallingConv::PTX_Kernel;
        ccmap["ptx_device"] = CallingConv::PTX_Device;
        ccmap["x86_64_sysvcc"] = CallingConv::X86_64_SysV;
        ccmap["win64cc"] = CallingConv::Win64;
        ccmap["spir_func"] = CallingConv::SPIR_FUNC;
        ccmap["spir_kernel"] = CallingConv::SPIR_KERNEL;
        ccmap["swiftcc"] = CallingConv::Swift;
#if LLVM_VERSION >= 130
        ccmap["swifttailcc"] = CallingConv::SwiftTail;
#endif
        ccmap["x86_intrcc"] = CallingConv::X86_INTR;
#if LLVM_VERSION < 170
        ccmap["hhvmcc"] = CallingConv::HHVM;
        ccmap["hhvm_ccc"] = CallingConv::HHVM_C;
#endif
        ccmap["amdgpu_vs"] = CallingConv::AMDGPU_VS;
        ccmap["amdgpu_ls"] = CallingConv::AMDGPU_LS;
        ccmap["amdgpu_hs"] = CallingConv::AMDGPU_HS;
        ccmap["amdgpu_es"] = CallingConv::AMDGPU_ES;
        ccmap["amdgpu_gs"] = CallingConv::AMDGPU_GS;
        ccmap["amdgpu_ps"] = CallingConv::AMDGPU_PS;
        ccmap["amdgpu_cs"] = CallingConv::AMDGPU_CS;
        ccmap["amdgpu_kernel"] = CallingConv::AMDGPU_KERNEL;
#if LLVM_VERSION >= 120
        ccmap["amdgpu_gfx"] = CallingConv::AMDGPU_Gfx;
#endif
    }
    auto entry = ccmap.find(cc);
    if (entry == ccmap.end()) {
        assert(false && "no such calling convention");
    }
    return entry->second;
}

static AtomicRMWInst::BinOp ParseAtomicBinOp(const char *op) {
    static std::map<std::string, AtomicRMWInst::BinOp> opmap;
    static bool init = false;
    if (!init) {
        init = true;
        opmap["xchg"] = AtomicRMWInst::BinOp::Xchg;
        opmap["add"] = AtomicRMWInst::BinOp::Add;
        opmap["sub"] = AtomicRMWInst::BinOp::Sub;
        opmap["and"] = AtomicRMWInst::BinOp::And;
        opmap["nand"] = AtomicRMWInst::BinOp::Nand;
        opmap["or"] = AtomicRMWInst::BinOp::Or;
        opmap["xor"] = AtomicRMWInst::BinOp::Xor;
        opmap["max"] = AtomicRMWInst::BinOp::Max;
        opmap["min"] = AtomicRMWInst::BinOp::Min;
        opmap["umax"] = AtomicRMWInst::BinOp::UMax;
        opmap["umin"] = AtomicRMWInst::BinOp::UMin;
        opmap["fadd"] = AtomicRMWInst::BinOp::FAdd;
        opmap["fsub"] = AtomicRMWInst::BinOp::FSub;
#if LLVM_VERSION >= 150
        opmap["fmax"] = AtomicRMWInst::BinOp::FMax;
        opmap["fmin"] = AtomicRMWInst::BinOp::FMin;
#endif
    }
    auto entry = opmap.find(op);
    if (entry == opmap.end()) {
        assert(false && "no such atomic binop");
    }
    return entry->second;
}

static AtomicOrdering ParseAtomicOrdering(const char *ordering) {
    static std::map<std::string, AtomicOrdering> ordermap;
    static bool init = false;
    if (!init) {
        init = true;
        ordermap["unordered"] = AtomicOrdering::Unordered;
        ordermap["monotonic"] = AtomicOrdering::Monotonic;
        ordermap["acquire"] = AtomicOrdering::Acquire;
        ordermap["release"] = AtomicOrdering::Release;
        ordermap["acq_rel"] = AtomicOrdering::AcquireRelease;
        ordermap["seq_cst"] = AtomicOrdering::SequentiallyConsistent;
    }
    auto entry = ordermap.find(ordering);
    if (entry == ordermap.end()) {
        assert(false && "no such atomic ordering");
    }
    return entry->second;
}

static SyncScope::ID ParseAtomicSyncScope(Module *M, const char *syncscope) {
    if (!syncscope) return SyncScope::System;

    static std::map<std::string, SyncScope::ID> scopemap;
    static bool init = false;
    if (!init) {
        init = true;

        // Fetch the registered memory scopes from LLVM.
        // Note: these are often target specific.
        SmallVector<StringRef, 16> scopes;
        M->getContext().getSyncScopeNames(scopes);

        for (auto scope : scopes) {
            scopemap[scope.str()] = M->getContext().getOrInsertSyncScopeID(scope);
        }
    }
    auto entry = scopemap.find(syncscope);
    if (entry == scopemap.end()) {
        assert(false && "no such memory scope");
    }
    return entry->second;
}

const int COMPILATION_UNIT_POS = 1;
static int terra_deletefunction(lua_State *L);

Function *EmitFunction(TerraCompilationUnit *CU, Obj *funcobj, TerraFunctionState *user);

struct Locals {
    Obj cur;
    Locals *prev;
};  // stack of local environment

struct FunctionEmitter {
    TerraCompilationUnit *CU;
    terra_State *T;
    lua_State *L;
    terra_CompilerState *C;
    Types *Ty;
    CCallingConv *CC;
    Module *M;
    Obj *labels, *labeldepth;
    Locals *locals;

    IRBuilder<> *B;
    std::vector<std::pair<BasicBlock *, size_t> >
            breakpoints;  // stack of basic blocks where a break statement should go

    DIBuilder *DB;
    DISubprogram *SP;

    StringMap<MDNode *> filenamecache;  // map from filename to lexical scope object
                                        // representing file.
    const char *customfilename;
    int customlinenumber;

    Obj *funcobj;
    TerraFunctionState *fstate;
    std::vector<BasicBlock *> deferred;

    Obj labeltbl;
    Locals basescope;

    FunctionEmitter(TerraCompilationUnit *CU_)
            : CU(CU_),
              T(CU_->T),
              L(CU_->T->L),
              C(CU_->T->C),
              Ty(CU_->Ty),
              CC(CU_->CC),
              M(CU_->M),
              locals(NULL) {
        B = new IRBuilder<>(*CU->TT->ctx);
        enterScope(&basescope);
        labels = newMap(&labeltbl);
    }
    ~FunctionEmitter() { delete B; }
    TerraFunctionState *emitFunction(Obj *funcobj_) {
        funcobj = funcobj_;
        fstate = lookupSymbol<TerraFunctionState>(CU->symbols, funcobj);
        if (!fstate) {
            fstate = (TerraFunctionState *)lua_newuserdata(
                    L, sizeof(TerraFunctionState));  // map the declaration first so that
                                                     // recursive uses do not re-emit
            memset(fstate, 0, sizeof(TerraFunctionState));
            mapFunction(CU->symbols, funcobj);
            const char *name = funcobj->string("name");
            bool isextern = T_functionextern == funcobj->kind("kind");
            if (isextern) {  // try to resolve function as imported C code
                fstate->func = M->getFunction(name);
                if (!fstate->func) {
                    GlobalValue *externfunction = CU->TT->external->getFunction(name);
                    if (externfunction) {
                        llvmutil_copyfrommodule(CU->M, CU->TT->external, &externfunction,
                                                1, AlwaysShouldCopy, NULL);
                        fstate->func = CU->M->getFunction(name);
                        assert(fstate->func);
                    }
                }
                if (fstate->func) return fstate;
            }

            CallingConv::ID callingconv = CallingConv::MaxID;
            if (funcobj->hasfield("callingconv")) {
                callingconv = ParseCallingConv(funcobj->string("callingconv"));
            }

            Obj ftype;
            funcobj->obj("type", &ftype);
            // function name is $+name so that it can't conflict with any symbols imported
            // from the C namespace
            fstate->func =
                    CC->CreateFunction(M, &ftype, callingconv,
                                       Twine(StringRef((isextern) ? "" : "$"), name));
            if (isextern) {
                // Set external linkage for extern functions.
                fstate->func->setLinkage(GlobalValue::ExternalLinkage);
            }
            if (callingconv != CallingConv::MaxID) {
                fstate->func->setCallingConv(callingconv);
            }

            if (funcobj->hasfield("alwaysinline")) {
                if (funcobj->boolean("alwaysinline")) {
                    fstate->func->addFnAttr(Attribute::AlwaysInline);
                } else {
                    fstate->func->addFnAttr(Attribute::NoInline);
                }
            }
            if (funcobj->hasfield("dontoptimize")) {
                if (funcobj->boolean("dontoptimize")) {
                    fstate->func->addFnAttr(Attribute::OptimizeNone);
                    fstate->func->addFnAttr(Attribute::NoInline);
                }
            }
            if (funcobj->hasfield("noreturn")) {
                if (funcobj->boolean("noreturn")) {
                    fstate->func->addFnAttr(Attribute::NoReturn);
                }
            }

            if (!isextern) {
                if (CU->optimize) {
                    fstate->index = CU->functioncount++;
                    fstate->lowlink = fstate->index;
                    fstate->onstack = true;
                    CU->tooptimize->push_back(fstate);
                }
                emitBody();
                if (CU->optimize &&
                    fstate->lowlink ==
                            fstate->index) {  // this is the end of a strongly connect
                                              // component run optimizations on it
                    VERBOSE_ONLY(T) { printf("optimizing scc containing: "); }
                    TerraFunctionState *f;
                    std::vector<Function *> scc;
                    do {
                        f = CU->tooptimize->back();
                        CU->tooptimize->pop_back();
                        scc.push_back(f->func);
                        f->onstack = false;
                        VERBOSE_ONLY(T) {
                            std::string s = f->func->getName().str();
                            printf("%s%s", s.c_str(), (fstate == f) ? "\n" : " ");
                        }
                    } while (fstate != f);
#if LLVM_VERSION < 170
                    // FIXME (Elliott): need to restore the manual inliner in LLVM 17
                    CU->mi->run(scc.begin(), scc.end());
#endif
                    for (size_t i = 0; i < scc.size(); i++) {
                        VERBOSE_ONLY(T) {
                            std::string s = scc[i]->getName().str();
                            printf("optimizing %s\n", s.c_str());
                        }
                        CU->fpm->run(*scc[i]
#if LLVM_VERSION >= 170
                                     ,
                                     CU->fam
#endif
                        );
                        VERBOSE_ONLY(T) { TERRA_DUMP_FUNCTION(scc[i]); }
                    }
                }
            }
            lua_getfield(L, COMPILATION_UNIT_POS, "collectfunctions");
            if (lua_toboolean(L, -1)) {  // set a destructor on the TerraFunctionState
                                         // object to clean up this function
                CU->nreferences++;
                CU->symbols->push();
                funcobj->push();
                lua_gettable(L, -2);  // lookup userdata object that holds the
                                      // TerraFunctionState for this function
                lua_newtable(
                        L);  // setmetatable(ud,{ __gc = terra_deletefunction(llvm_cu) })
                lua_getfield(L, COMPILATION_UNIT_POS, "llvm_cu");
                lua_pushcclosure(L, terra_deletefunction, 1);
                lua_setfield(L, -2, "__gc");
                lua_setmetatable(L, -2);
                lua_pop(L, 2);  // userdata object and symbols talbe
            }
            lua_pop(L, 1);
        }
        return fstate;
    }
    Constant *emitConstantExpression(Obj *exp) {
        TerraFunctionState state;
        fstate = &state;
        fstate->func = Function::Create(FunctionType::get(typeOfValue(exp)->type, false),
                                        Function::ExternalLinkage, "constant", M);
        BasicBlock *entry = BasicBlock::Create(*CU->TT->ctx, "entry", fstate->func);
        initDebug(exp->string("filename"), exp->number("linenumber"));
        setDebugPoint(exp);
        B->SetInsertPoint(entry);
        B->CreateRet(emitExp(exp));
        endDebug();
        CU->fpm->run(*fstate->func
#if LLVM_VERSION >= 170
                     ,
                     CU->fam
#endif
        );
        ReturnInst *term =
                cast<ReturnInst>(fstate->func->getEntryBlock().getTerminator());
        Constant *r = dyn_cast<Constant>(term->getReturnValue());
        assert(r || !"constant expression was not constant");
        fstate->func->eraseFromParent();
        return r;
    }
    Obj *newMap(Obj *buf) {
        lua_newtable(L);
        CU->symbols->fromStack(buf);
        return buf;
    }
    void emitBody() {
        BasicBlock *entry = BasicBlock::Create(*CU->TT->ctx, "entry", fstate->func);
        B->SetInsertPoint(entry);

        Obj parameters;
        initDebug(funcobj->string("filename"), funcobj->number("linenumber"));
        setDebugPoint(funcobj);
        funcobj->obj("parameters", &parameters);

        Obj ftype, labeldepthtbl;
        funcobj->obj("type", &ftype);
        funcobj->obj("labeldepths", &labeldepthtbl);
        labeldepth = &labeldepthtbl;

        std::vector<Value *> parametervars;
        emitExpressionList(&parameters, false, &parametervars);
        CC->EmitEntry(B, &ftype, fstate->func, &parametervars);

        Obj body;
        funcobj->obj("body", &body);
        emitStmt(&body);
        // if there no terminating return statment, we need to insert one
        // if there was a Return, then this block is dead and will be cleaned up
        emitReturnUndef();
        assert(breakpoints.size() == 0);

        VERBOSE_ONLY(T) { TERRA_DUMP_FUNCTION(fstate->func); }
        verifyFunction(*fstate->func);

        endDebug();
    }
    template <typename R>
    R *lookupSymbol(Obj *tbl, Obj *k) {
        return (R *)tbl->getud(k);
    }
    void mapSymbol(Obj *tbl, Obj *k, void *v) { tbl->setud(k, v); }
    void mapFunction(Obj *tbl, Obj *k) {  // TerraFunctionState userdata is on top of
                                          // stack
        tbl->push();
        k->push();
        lua_pushvalue(L, -3);
        lua_settable(L, -3);
        lua_pop(L, 2);  // table and original userdata object
    }
    TType *getType(Obj *v) { return Ty->Get(v); }
    TType *typeOfValue(Obj *v) {
        Obj t;
        v->obj("type", &t);
        return getType(&t);
    }

    AllocaInst *allocVar(Obj *v) {
        Obj sym;
        v->obj("symbol", &sym);
        AllocaInst *a = CreateAlloca(B, typeOfValue(v)->type, 0, v->string("name"));
        mapSymbol(&locals->cur, &sym, a);
        return a;
    }

    Value *emitAddressOf(Obj *exp, Obj *as_type = NULL) {
        Value *v = emitExp(exp, false);
        // if it's not already an lvalue, root it
        if (!exp->boolean("lvalue")) {
            Value *addr = CreateAlloca(B, typeOfValue(exp)->type);
            B->CreateStore(v, addr);
            v = addr;
        }

        // make sure it has the correct addrspace (if requested)
        if (as_type != NULL) {
            Type *t = typeOfValue(as_type)->type;
            if (t->getPointerAddressSpace() != v->getType()->getPointerAddressSpace())
                v = B->CreateAddrSpaceCast(v, t);
        }
        return v;
    }

    Value *emitUnary(Obj *exp, Obj *ao) {
        T_Kind kind = exp->kind("operator");
        if (T_addressof == kind) return emitAddressOf(ao, exp);

        TType *t = typeOfValue(exp);
        Type *baseT = getPrimitiveType(t);
        Value *a = emitExp(ao);
        switch (kind) {
            case T_dereference:
                return a; /* no-op, a is a pointer and lvalue is true for this expression
                           */
                break;
            case T_not:
                if (t->islogical)
                    return B->CreateZExt(B->CreateICmpEQ(a, ConstantInt::get(t->type, 0)),
                                         t->type);
                else
                    return B->CreateNot(a);
                break;
            case T_sub:
                if (baseT->isIntegerTy()) {
                    return B->CreateNeg(a);
                } else {
                    B->setFastMathFlags(CU->fastmath);
                    return B->CreateFNeg(a);
                }
                break;
            default:
                printf("NYI - unary %s\n", tkindtostr(kind));
                abort();
                break;
        }
    }
    Value *emitCompare(T_Kind op, TType *t, Value *a, Value *b) {
        Type *baseT = getPrimitiveType(t);
#define RETURN_OP(op, u)                                   \
    if (baseT->isIntegerTy() || t->type->isPointerTy()) {  \
        return B->CreateICmp(CmpInst::ICMP_##op, a, b);    \
    } else {                                               \
        B->setFastMathFlags(CU->fastmath);                 \
        return B->CreateFCmp(CmpInst::FCMP_##u##op, a, b); \
    }
#define RETURN_SOP(op, u)                                    \
    if (baseT->isIntegerTy() || t->type->isPointerTy()) {    \
        if (t->issigned) {                                   \
            return B->CreateICmp(CmpInst::ICMP_S##op, a, b); \
        } else {                                             \
            return B->CreateICmp(CmpInst::ICMP_U##op, a, b); \
        }                                                    \
    } else {                                                 \
        B->setFastMathFlags(CU->fastmath);                   \
        return B->CreateFCmp(CmpInst::FCMP_##u##op, a, b);   \
    }

        switch (op) {
            case T_ne:
                RETURN_OP(NE, U) break;
            case T_eq:
                RETURN_OP(EQ, O) break;
            case T_lt:
                RETURN_SOP(LT, O) break;
            case T_gt:
                RETURN_SOP(GT, O) break;
            case T_ge:
                RETURN_SOP(GE, O) break;
            case T_le:
                RETURN_SOP(LE, O) break;
            default:
                assert(!"unknown op");
                return NULL;
                break;
        }
#undef RETURN_OP
#undef RETURN_SOP
    }
    void emitBranchOnExpr(Obj *expr, BasicBlock *trueblock, BasicBlock *falseblock) {
        // try to optimize the branching by looking into lazy logical expressions and
        // simplifying them
        T_Kind kind = expr->kind("kind");
        if (T_operator == kind) {
            T_Kind op = expr->kind("operator");
            Obj operands;
            expr->obj("operands", &operands);
            Obj lhs;
            Obj rhs;
            operands.objAt(0, &lhs);
            operands.objAt(1, &rhs);
            if (T_not == op) {
                emitBranchOnExpr(&lhs, falseblock, trueblock);
                return;
            }
            if (T_and == op || T_or == op) {
                bool isand = T_and == op;
                BasicBlock *condblock =
                        createAndInsertBB((isand) ? "and.lhs.true" : "or.lhs.false");
                emitBranchOnExpr(&lhs, (isand) ? condblock : trueblock,
                                 (isand) ? falseblock : condblock);
                setInsertBlock(condblock);
                emitBranchOnExpr(&rhs, trueblock, falseblock);
                return;
            }
        }
        // if no optimizations applied just emit the naive branch
        B->CreateCondBr(emitCond(expr), trueblock, falseblock);
    }
    Value *emitLazyLogical(TType *t, Obj *ao, Obj *bo, bool isAnd) {
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

        BasicBlock *stmtB = createAndInsertBB((isAnd) ? "and.rhs" : "or.rhs");
        BasicBlock *mergeB = createAndInsertBB((isAnd) ? "and.end" : "or.end");

        emitBranchOnExpr(ao, (isAnd) ? stmtB : mergeB, (isAnd) ? mergeB : stmtB);

        Type *int1 = Type::getInt1Ty(*CU->TT->ctx);
        setInsertBlock(mergeB);
        PHINode *result = B->CreatePHI(int1, 2);
        Value *literal = ConstantInt::get(int1, !isAnd);
        for (pred_iterator it = pred_begin(mergeB), end = pred_end(mergeB); it != end;
             ++it)
            result->addIncoming(literal, *it);

        setInsertBlock(stmtB);
        Value *b = emitCond(bo);
        stmtB = B->GetInsertBlock();
        B->CreateBr(mergeB);
        followsBB(mergeB);
        setInsertBlock(mergeB);
        result->addIncoming(b, stmtB);
        return B->CreateZExt(result, t->type);
    }
    Value *emitIndex(TType *ftype, int tobits, Value *number) {
        TType ttype;
        memset(&ttype, 0, sizeof(ttype));
        ttype.type = Type::getIntNTy(*CU->TT->ctx, tobits);
        ttype.issigned = ftype->issigned;
        return emitPrimitiveCast(ftype, &ttype, number);
    }
    Value *emitPointerArith(T_Kind kind, Obj *ptrTy, Value *pointer, TType *numTy,
                            Value *number) {
        Obj objTy;
        Types::PointsToType(ptrTy, &objTy);

        number = emitIndex(numTy, 64, number);
        if (kind == T_add) {
            return B->CreateGEP(getType(&objTy)->type, pointer, number);
        } else if (kind == T_sub) {
            Value *numNeg = B->CreateNeg(number);
            return B->CreateGEP(getType(&objTy)->type, pointer, numNeg);
        } else {
            assert(!"unexpected pointer arith");
            return NULL;
        }
    }
    Value *emitPointerSub(Obj *ptrTy, Value *a, Value *b) {
        Obj objTy;
        Types::PointsToType(ptrTy, &objTy);
        return B->CreatePtrDiff(
#if LLVM_VERSION >= 140
                getType(&objTy)->type,
#endif
                a, b);
    }
    Value *emitBinary(Obj *exp, Obj *ao, Obj *bo) {
        TType *t = typeOfValue(exp);
        T_Kind kind = exp->kind("operator");

        // check for lazy operators before evaluateing arguments
        if (t->islogical && !t->type->isVectorTy()) {
            switch (kind) {
                case T_and:
                    return emitLazyLogical(t, ao, bo, true);
                case T_or:
                    return emitLazyLogical(t, ao, bo, false);
                default:
                    break;
            }
        }

        // ok, we have eager operators, lets evalute the arguments then emit
        Value *a = emitExp(ao);
        Value *b = emitExp(bo);

        Obj aot;
        ao->obj("type", &aot);
        TType *at = getType(&aot);
        TType *bt = typeOfValue(bo);
        // CC.EnsureTypeIsComplete(at) (not needed because typeOfValue(ao) ensure the type
        // is complete)

        // check for pointer arithmetic first pointer arithmetic first
        if (at->type->isPointerTy() && (kind == T_add || kind == T_sub)) {
            Ty->EnsurePointsToCompleteType(&aot);
            if (bt->type->isPointerTy()) {
                assert(kind == T_sub);
                return emitPointerSub(&aot, a, b);
            } else {
                assert(bt->type->isIntegerTy());
                return emitPointerArith(kind, &aot, a, bt, b);
            }
        }

        Type *baseT = getPrimitiveType(t);

#define RETURN_OP(op)                      \
    if (baseT->isIntegerTy()) {            \
        return B->Create##op(a, b);        \
    } else {                               \
        B->setFastMathFlags(CU->fastmath); \
        return B->CreateF##op(a, b);       \
    }
#define RETURN_SOP(op)                     \
    if (baseT->isIntegerTy()) {            \
        if (t->issigned) {                 \
            return B->CreateS##op(a, b);   \
        } else {                           \
            return B->CreateU##op(a, b);   \
        }                                  \
    } else {                               \
        B->setFastMathFlags(CU->fastmath); \
        return B->CreateF##op(a, b);       \
    }
        switch (kind) {
            case T_add:
                RETURN_OP(Add) break;
            case T_sub:
                RETURN_OP(Sub) break;
            case T_mul:
                RETURN_OP(Mul) break;
            case T_div:
                RETURN_SOP(Div) break;
            case T_mod:
                RETURN_SOP(Rem) break;
            case T_pow:
                return B->CreateXor(a, b);
            case T_and:
                return B->CreateAnd(a, b);
            case T_or:
                return B->CreateOr(a, b);
            case T_ne:
            case T_eq:
            case T_lt:
            case T_gt:
            case T_ge:
            case T_le: {
                Value *v = emitCompare(exp->kind("operator"), typeOfValue(ao), a, b);
                return B->CreateZExt(v, t->type);
            } break;
            case T_lshift:
                return B->CreateShl(a, b);
                break;
            case T_rshift:
                if (at->issigned)
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
        // should not be reachable - every case above should either return or assert
        return 0;
    }
    Value *emitArrayToPointer(Obj *exp) {
        TType *t = typeOfValue(exp);
        Value *v = emitAddressOf(exp);
        return CreateConstGEP2_32(B, v, t->type, 0, 0);
    }
    Type *getPrimitiveType(TType *t) {
        if (t->type->isVectorTy())
            return cast<VectorType>(t->type)->getElementType();
        else
            return t->type;
    }
    Value *emitPrimitiveCast(TType *from, TType *to, Value *exp) {
        Type *fBase = getPrimitiveType(from);
        Type *tBase = getPrimitiveType(to);

        int fsize = fBase->getPrimitiveSizeInBits();
        int tsize = tBase->getPrimitiveSizeInBits();

        if (fBase->isIntegerTy()) {
            if (tBase->isIntegerTy()) {
                if (to->islogical) {
                    return B->CreateZExt(B->CreateICmpNE(exp, ConstantInt::get(fBase, 0)),
                                         tBase);
                } else {
                    return B->CreateIntCast(exp, to->type, from->issigned);
                }
            } else if (tBase->isFloatingPointTy()) {
                if (from->issigned) {
                    return B->CreateSIToFP(exp, to->type);
                } else {
                    return B->CreateUIToFP(exp, to->type);
                }
            } else
                goto nyi;
        } else if (fBase->isFloatingPointTy()) {
            if (tBase->isIntegerTy()) {
                if (to->issigned) {
                    return B->CreateFPToSI(exp, to->type);
                } else {
                    return B->CreateFPToUI(exp, to->type);
                }
            } else if (tBase->isFloatingPointTy()) {
                if (fsize < tsize) {
                    return B->CreateFPExt(exp, to->type);
                } else {
                    return B->CreateFPTrunc(exp, to->type);
                }
            } else
                goto nyi;
        } else
            goto nyi;
    nyi:
        assert(!"NYI - casts");
        return NULL;
    }
    Value *emitBroadcast(TType *fromT, TType *toT, Value *v) {
        Value *result = UndefValue::get(toT->type);
        VectorType *vt = cast<VectorType>(toT->type);
        Type *integerType = Type::getInt32Ty(*CU->TT->ctx);
#if LLVM_VERSION < 120
        for (size_t i = 0; i < vt->getNumElements(); i++)
#else
        for (size_t i = 0; i < vt->getElementCount().getKnownMinValue(); i++)
#endif
            result = B->CreateInsertElement(result, v, ConstantInt::get(integerType, i));
        return result;
    }
#if LLVM_VERSION < 170
    bool isPointerToFunction(Type *t) {
        return t->isPointerTy() && t->getPointerElementType()->isFunctionTy();
    }
#endif
    Value *emitStructSelect(Obj *structType, Value *structPtr, int index,
                            Obj *entryType) {
        assert(structPtr->getType()->isPointerTy());
#if LLVM_VERSION < 170
        assert(structPtr->getType()->getPointerElementType()->isStructTy());
#endif
        Ty->EnsureTypeIsComplete(structType);

        Obj layout;
        GetStructEntries(structType, &layout);

        Obj entry;
        layout.objAt(index, &entry);

        int allocindex = entry.number("allocation");

        Value *addr = CreateConstGEP2_32(B, structPtr, getType(structType)->type, 0,
                                         allocindex);
        // in three cases the type of the value in the struct does not match the expected
        // type returned
        // 1. if it is a union then the llvm struct will have some buffer space to hold
        // the object but
        //   the space may have a different type
        // 2. if the struct was imported from Clang and the value is a function pointer
        // (Terra internal represents functions with i8* for simplicity)
        // 3. if the field was an anonymous C struct, so we don't know its name
        // in all cases we simply bitcast cast the resulting pointer to the expected type
        entry.obj("type", entryType);
        TType *entryTType = getType(entryType);
        if (entry.boolean("inunion")
#if LLVM_VERSION < 170
            || isPointerToFunction(entryTType->type)
#endif
        ) {
            unsigned as = addr->getType()->getPointerAddressSpace();
            Type *resultType = PointerType::get(entryTType->type, as);
            addr = B->CreateBitCast(addr, resultType);
        }

        return addr;
    }

    Value *emitStore(Value *value, Value *addr, bool isVolatile, MaybeAlign alignment) {
        LoadInst *l = dyn_cast<LoadInst>(&*value);
        Type *t1 = value->getType();
        if ((t1->isStructTy() || t1->isArrayTy()) && l) {
#if LLVM_VERSION < 170
            unsigned as_dst = addr->getType()->getPointerAddressSpace();
            // create bitcasts of src and dest address
            Type *t_dst = Type::getInt8PtrTy(*CU->TT->ctx, as_dst);
            // addr_dst
            Value *addr_dst = B->CreateBitCast(addr, t_dst);
            // addr_src
            Value *addr_src = l->getOperand(0);
            unsigned as_src = addr_src->getType()->getPointerAddressSpace();
            Type *t_src = Type::getInt8PtrTy(*CU->TT->ctx, as_src);
            addr_src = B->CreateBitCast(addr_src, t_src);
#else
            Value *addr_dst = addr;
            Value *addr_src = l->getOperand(0);
#endif
            uint64_t size = 0;
            MaybeAlign a1;
            if (t1->isStructTy()) {
                // size of bytes to copy
                StructType *st = cast<StructType>(t1);
                const StructLayout *sl = CU->getDataLayout().getStructLayout(st);
                size = sl->getSizeInBytes();
                if (!alignment) {
                    a1 = sl->getAlignment();
                }
            } else if (t1->isArrayTy() && (CU->getDataLayout().getTypeAllocSize(t1) >=
                                           MEM_ARRAY_THRESHOLD)) {
                size = CU->getDataLayout().getTypeAllocSize(t1);
                if (!alignment) {
                    a1 = MaybeAlign(CU->getDataLayout().getABITypeAlign(t1));
                }
            } else {
                StoreInst *st = B->CreateStore(value, addr);
                if (isVolatile) st->setVolatile(true);
                if (alignment) st->setAlignment(*alignment);
                return st;
            }
            Value *size_v = ConstantInt::get(Type::getInt64Ty(*CU->TT->ctx), size);
            // perform the copy
            Value *m = B->CreateMemCpy(addr_dst, a1, addr_src,
                                       MaybeAlign(
#if LLVM_VERSION < 150
                                               l->getAlignment()
#else
                                               l->getAlign()
#endif
                                                       ),
                                       size_v, isVolatile);
            return m;
        } else {
            StoreInst *st = B->CreateStore(value, addr);
            if (isVolatile) st->setVolatile(true);
            if (alignment) st->setAlignment(*alignment);
            return st;
        }
    }

    Value *emitIfElse(Obj *cond, Obj *a, Obj *b) {
        Value *condExp = emitExp(cond);
        Value *aExp = emitExp(a);
        Value *bExp = emitExp(b);
        condExp = emitCond(condExp);  // convert to i1
        return B->CreateSelect(condExp, aExp, bExp);
    }
    Value *emitExp(Obj *exp, bool loadlvalue = true) {
        Value *raw = emitExpRaw(exp);
        if (loadlvalue && exp->boolean("lvalue")) {
            Obj type;
            exp->obj("type", &type);
            Ty->EnsureTypeIsComplete(&type);
            Type *ttype = getType(&type)->type;
            raw = B->CreateLoad(ttype, raw);
        }
        return raw;
    }

    Value *emitExpRaw(Obj *exp) {
        setDebugPoint(exp);
        switch (exp->kind("kind")) {
            case T_var: {
                Obj sym;
                exp->obj("symbol", &sym);
                Value *v = NULL;
                for (Locals *f = locals; v == NULL && f != NULL; f = f->prev) {
                    v = lookupSymbol<Value>(&f->cur, &sym);
                }
                assert(v);
                return v;
            } break;
            case T_globalvalueref: {
                Obj global;
                exp->obj("value", &global);
                if (T_globalvariable == global.kind("kind")) {
                    GlobalVariable *gv =
                            EmitGlobalVariable(CU, &global, exp->string("name"));
#if LLVM_VERSION < 170
                    // Clang (as of LLVM 7) changes the types of certain globals
                    // (like arrays). Change the type back to what we expect
                    // here so we don't cause issues downstream in the compiler.
                    return B->CreateBitCast(
                            gv,
                            PointerType::get(typeOfValue(exp)->type,
                                             gv->getType()->getPointerAddressSpace()));
#else
                    return gv;
#endif
                } else {
#if LLVM_VERSION < 170
                    // functions are represented with &int8 pointers to avoid
                    // calling convension issues, so cast the literal to this type now
                    return B->CreateBitCast(EmitFunction(CU, &global, fstate),
                                            typeOfValue(exp)->type);
#else
                    return EmitFunction(CU, &global, fstate);
#endif
                }
            } break;
            case T_allocvar: {
                return allocVar(exp);
            } break;
            case T_letin: {
                Locals buf;
                enterScope(&buf);
                Value *v = emitLetIn(exp);
                leaveScope();
                return v;
            } break;
            case T_operator: {
                Obj exps;
                exp->obj("operands", &exps);
                int N = exps.size();
                if (N == 1) {
                    Obj a;
                    exps.objAt(0, &a);
                    return emitUnary(exp, &a);
                } else if (N == 2) {
                    Obj a, b;
                    exps.objAt(0, &a);
                    exps.objAt(1, &b);
                    return emitBinary(exp, &a, &b);
                } else {
                    T_Kind op = exp->kind("operator");
                    if (op == T_select) {
                        Obj a, b, c;
                        exps.objAt(0, &a);
                        exps.objAt(1, &b);
                        exps.objAt(2, &c);
                        return emitIfElse(&a, &b, &c);
                    }
                    exp->dump();
                    assert(!"NYI - unimplemented operator?");
                    return NULL;
                }
                switch (exp->kind("operator")) {
                    case T_add: {
                        TType *t = typeOfValue(exp);
                        Obj exps;

                        if (t->type->isFPOrFPVectorTy()) {
                            Obj a, b;
                            exps.objAt(0, &a);
                            exps.objAt(1, &b);
                            B->setFastMathFlags(CU->fastmath);
                            return B->CreateFAdd(emitExp(&a), emitExp(&b));
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
                exp->obj("value", &value);
                exp->obj("index", &idx);

                Obj aggTypeO;
                value.obj("type", &aggTypeO);
                TType *aggType = getType(&aggTypeO);
                Value *valueExp = emitExp(&value);
                Value *idxExp = emitExp(&idx);

                // if this is a vector index, emit an extractElement
                if (aggType->type->isVectorTy()) {
                    idxExp = emitIndex(typeOfValue(&idx), 32, idxExp);
                    Value *result = B->CreateExtractElement(valueExp, idxExp);
                    return result;
                } else {
                    assert(aggType->type->isPointerTy());
                    Obj objType;
                    Types::PointsToType(&aggTypeO, &objType);
                    TType *objTType = getType(&objType);

                    idxExp = emitIndex(typeOfValue(&idx), 64, idxExp);
                    // otherwise we have a pointer access which will use a GEP instruction
                    std::vector<Value *> idxs;
                    Ty->EnsurePointsToCompleteType(&aggTypeO);
                    Value *result = B->CreateGEP(objTType->type, valueExp, idxExp);
                    if (!exp->boolean("lvalue"))
                        result = B->CreateLoad(objTType->type, result);
                    return result;
                }
            } break;
            case T_literal: {
                Obj type;
                exp->obj("type", &type);
                TType *t = getType(&type);
                if (t->islogical) {
                    bool b = exp->boolean("value");
                    return ConstantInt::get(t->type, b);
                } else if (t->type->isIntegerTy()) {
                    uint64_t integer = exp->integer("value");
                    return ConstantInt::get(t->type, integer);
                } else if (t->type->isFloatingPointTy()) {
                    double dbl = exp->number("value");
                    return ConstantFP::get(t->type, dbl);
                } else if (t->type->isPointerTy()) {
                    PointerType *pt = cast<PointerType>(t->type);
                    if (type.kind("kind") == T_niltype) {
                        return ConstantPointerNull::get(pt);
                    }

                    Obj objType;
                    Types::PointsToType(&type, &objType);
                    if (getType(&objType)->type->isIntegerTy(8)) {
                        Obj stringvalue;
                        exp->obj("value", &stringvalue);
                        Value *str = lookupSymbol<Value>(CU->symbols, &stringvalue);
                        if (!str) {
                            exp->pushfield("value");
                            size_t len;
                            const char *rawstr = lua_tolstring(L, -1, &len);
                            str = B->CreateGlobalString(
                                    StringRef(rawstr, len),
                                    "$string");  // needs a name to make mcjit work in 3.5
                            lua_pop(L, 1);
                            mapSymbol(CU->symbols, &stringvalue, str);
                        }
#if LLVM_VERSION < 170
                        return B->CreateBitCast(str, pt);
#else
                        return str;
#endif
                    } else {
                        assert(!"NYI - pointer literal");
                    }
                } else {
                    exp->dump();
                    assert(!"NYI - literal");
                }
            } break;
            case T_constant: {
                TType *typ = typeOfValue(exp);
                Obj value;
                exp->pushfield("value");
                const void *data = lua_topointer(L, -1);
                assert(data);
                size_t size = CU->getDataLayout().getTypeAllocSize(typ->type);
                Value *r;
                if (typ->type->isIntegerTy()) {
                    uint64_t integer = 0;
                    memcpy(&integer, data, size);  // note: assuming little endian, there
                                                   // is probably a better way to do this
                    r = ConstantInt::get(typ->type, integer);
                } else if (typ->type->isFloatTy()) {
                    r = ConstantFP::get(typ->type, *(const float *)data);
                } else if (typ->type->isDoubleTy()) {
                    r = ConstantFP::get(typ->type, *(const double *)data);
                } else if (typ->type->isPointerTy()) {
                    Constant *ptrint = ConstantInt::get(
                            CU->getDataLayout().getIntPtrType(*CU->TT->ctx),
                            *(const intptr_t *)data);
                    r = ConstantExpr::getIntToPtr(ptrint, typ->type);
                } else {
                    TERRA_DUMP_TYPE(typ->type);
                    assert(!"NYI - constant load\n");
                }
                lua_pop(L, 1);  // remove pointer
                return r;
            } break;
            case T_apply: {
                return emitCall(exp, false);
            } break;
            case T_structcast: {
                Obj expression, structvariable, to;
                exp->obj("expression", &expression);
                // allocate memory to hold input variable
                exp->obj("structvariable", &structvariable);
                exp->obj("type", &to);
                TType *toT = getType(&to);
                Value *sv = allocVar(&structvariable);
                B->CreateStore(emitExp(&expression), sv);

                // allocate temporary to hold output variable
                // type must be complete before we try to allocate space for it
                // this is enforced by the callers
                assert(!toT->incomplete);
                Value *output = CreateAlloca(B, toT->type);

                Obj entries;
                exp->obj("entries", &entries);
                int N = entries.size();

                for (int i = 0; i < N; i++) {
                    Obj entry;
                    entries.objAt(i, &entry);
                    Obj value;
                    entry.obj("value", &value);
                    int idx = entry.number("index");
                    Obj entryType;
                    Value *oe = emitStructSelect(&to, output, idx, &entryType);
                    Value *in = emitExp(
                            &value);  // these expressions will select from the
                                      // structvariable and perform any casts necessary
                    B->CreateStore(in, oe);
                }
                return B->CreateLoad(toT->type, output);
            } break;
            case T_cast: {
                Obj a;
                Obj to, from;
                exp->obj("expression", &a);
                exp->obj("to", &to);
                a.obj("type", &from);
                TType *fromT = getType(&from);
                TType *toT = getType(&to);
                if (fromT->type->isArrayTy()) {
                    return emitArrayToPointer(&a);
                }
                Value *v = emitExp(&a);
                if (fromT->type->isPointerTy()) {
                    if (toT->type->isPointerTy()) {
#if LLVM_VERSION < 170
                        return B->CreateBitCast(v, toT->type);
#else
                        return v;
#endif
                    } else {
                        assert(toT->type->isIntegerTy());
                        return B->CreatePtrToInt(v, toT->type);
                    }
                } else if (toT->type->isPointerTy()) {
                    assert(fromT->type->isIntegerTy());
                    return B->CreateIntToPtr(v, toT->type);
                } else if (toT->type->isVectorTy()) {
                    if (fromT->type->isVectorTy())
                        return emitPrimitiveCast(fromT, toT, v);
                    else
                        return emitBroadcast(fromT, toT, v);
                } else {
                    return emitPrimitiveCast(fromT, toT, v);
                }
            } break;
            case T_sizeof: {
                Obj typ;
                exp->obj("oftype", &typ);
                TType *tt = getType(&typ);
                return ConstantInt::get(Type::getInt64Ty(*CU->TT->ctx),
                                        CU->getDataLayout().getTypeAllocSize(tt->type));
            } break;
            case T_select: {
                Obj obj, typ;
                exp->obj("value", &obj);
                /*TType * vt =*/typeOfValue(&obj);

                obj.obj("type", &typ);
                int offset = exp->number("index");

                Value *v = emitAddressOf(&obj);
                Obj entryType;
                Value *result = emitStructSelect(&typ, v, offset, &entryType);
                Type *ttype = getType(&typ)->type;
                if (!exp->boolean("lvalue"))
                    result = B->CreateLoad(getType(&entryType)->type, result);
                return result;
            } break;
            case T_constructor:
            case T_arrayconstructor: {
                Obj expressions;
                exp->obj("expressions", &expressions);
                return emitConstructor(exp, &expressions);
            } break;
            case T_vectorconstructor: {
                Obj expressions;
                exp->obj("expressions", &expressions);
                std::vector<Value *> values;
                emitExpressionList(&expressions, true, &values);
                TType *vecType = typeOfValue(exp);
                Value *vec = UndefValue::get(vecType->type);
                Type *intType = Type::getInt32Ty(*CU->TT->ctx);
                for (size_t i = 0; i < values.size(); i++) {
                    vec = B->CreateInsertElement(vec, values[i],
                                                 ConstantInt::get(intType, i));
                }
                return vec;
            } break;
            case T_inlineasm: {
                Obj arguments;
                exp->obj("arguments", &arguments);
                std::vector<Value *> values;
                emitExpressionList(&arguments, true, &values);
                Obj typ;
                exp->obj("type", &typ);
                bool isvoid = Ty->IsUnitType(&typ);
                Type *ttype = getType(&typ)->type;
                Type *rtype = (isvoid) ? Type::getVoidTy(*CU->TT->ctx) : ttype;
                std::vector<Type *> ptypes;
                for (size_t i = 0; i < values.size(); i++)
                    ptypes.push_back(values[i]->getType());
                InlineAsm *fn = InlineAsm::get(
                        FunctionType::get(rtype, ptypes, false), exp->string("asm"),
                        exp->string("constraints"), exp->boolean("volatile"));
                Value *call = B->CreateCall(fn->getFunctionType(), fn, values);
                return (isvoid) ? UndefValue::get(ttype) : call;
            } break;
            case T_attrload: {
                Obj addr, type, attr;
                exp->obj("type", &type);
                exp->obj("address", &addr);
                exp->obj("attrs", &attr);
                Ty->EnsureTypeIsComplete(&type);
                Type *ttype = getType(&type)->type;
                Value *v = emitExp(&addr);
                LoadInst *l = B->CreateLoad(ttype, v);
                if (attr.hasfield("alignment")) {
                    int alignment = attr.number("alignment");
                    l->setAlignment(Align(alignment));
                }
                if (attr.boolean("nontemporal")) {
                    auto list = ConstantAsMetadata::get(
                            ConstantInt::get(Type::getInt32Ty(*CU->TT->ctx), 1));
                    l->setMetadata("nontemporal", MDNode::get(*CU->TT->ctx, list));
                }
                l->setVolatile(attr.boolean("isvolatile"));
                return l;
            } break;
            case T_attrstore: {
                Obj addr, attr, value;
                exp->obj("address", &addr);
                exp->obj("attrs", &attr);
                exp->obj("value", &value);
                Value *addrexp = emitExp(&addr);
                Value *valueexp = emitExp(&value);
                bool isvolatile = attr.boolean("isvolatile");
                bool hasalignment = attr.hasfield("alignment");
                MaybeAlign alignment;
                if (hasalignment)
                    alignment =
                            MaybeAlign(static_cast<uint64_t>(attr.number("alignment")));
                Value *s = emitStore(valueexp, addrexp, isvolatile, alignment);
                StoreInst *store = dyn_cast<StoreInst>(s);
                if (store && attr.boolean("nontemporal")) {
                    auto list = ConstantAsMetadata::get(
                            ConstantInt::get(Type::getInt32Ty(*CU->TT->ctx), 1));
                    store->setMetadata("nontemporal", MDNode::get(*CU->TT->ctx, list));
                }
                return Constant::getNullValue(typeOfValue(exp)->type);
            } break;
            case T_fence: {
                Obj attr;
                exp->obj("attrs", &attr);
                bool has_syncscope = attr.hasfield("syncscope");
                SyncScope::ID syncscope = ParseAtomicSyncScope(
                        M, has_syncscope ? attr.string("syncscope") : NULL);
                AtomicOrdering ordering = ParseAtomicOrdering(attr.string("ordering"));
                if (ordering == AtomicOrdering::Unordered ||
                    ordering == AtomicOrdering::Monotonic) {
                    assert(false &&
                           "fence does not support unordered or monotonic ordering");
                }
                FenceInst *a = B->CreateFence(ordering, syncscope);
                return a;
            } break;
            case T_cmpxchg: {
                Obj addr, cmpvalue, newvalue, attr;
                exp->obj("address", &addr);
                exp->obj("cmp", &cmpvalue);
                exp->obj("new", &newvalue);
                exp->obj("attrs", &attr);
                Value *addrexp = emitExp(&addr);
                Value *cmpexp = emitExp(&cmpvalue);
                Value *newexp = emitExp(&newvalue);
                bool has_syncscope = attr.hasfield("syncscope");
                SyncScope::ID syncscope = ParseAtomicSyncScope(
                        M, has_syncscope ? attr.string("syncscope") : NULL);
                AtomicOrdering success_ordering =
                        ParseAtomicOrdering(attr.string("success_ordering"));
                AtomicOrdering failure_ordering =
                        ParseAtomicOrdering(attr.string("failure_ordering"));
                bool has_alignment = attr.hasfield("alignment");
#if LLVM_VERSION >= 130
                MaybeAlign alignment;
                if (has_alignment) {
                    alignment = MaybeAlign(attr.number("alignment"));
                }
#endif
                AtomicCmpXchgInst *a = B->CreateAtomicCmpXchg(
                        addrexp, cmpexp, newexp,
#if LLVM_VERSION >= 130
                        alignment,
#endif
                        success_ordering, failure_ordering, syncscope);
                a->setVolatile(attr.boolean("isvolatile"));
                a->setWeak(attr.boolean("isweak"));
                if (has_alignment) {
#if LLVM_VERSION < 130
                    a->setAlignment(Align(attr.number("alignment")));
#endif
                }
                Value *a_result = B->CreateExtractValue(a, ArrayRef<unsigned>(0));
                Value *a_success = B->CreateExtractValue(a, ArrayRef<unsigned>(1));
                Value *a_success_i8 = B->CreateZExt(a_success, B->getInt8Ty());
                Type *elt_types[2] = {a_result->getType(), B->getInt8Ty()};
                Type *result_type = typeOfValue(exp)->type;
                Value *result = UndefValue::get(result_type);
                result = B->CreateInsertValue(result, a_result, ArrayRef<unsigned>(0));
                result =
                        B->CreateInsertValue(result, a_success_i8, ArrayRef<unsigned>(1));
                return result;
            } break;
            case T_atomicrmw: {
                AtomicRMWInst::BinOp op = ParseAtomicBinOp(exp->string("operator"));
                Obj addr, value, attr;
                exp->obj("address", &addr);
                exp->obj("value", &value);
                exp->obj("attrs", &attr);
                Value *addrexp = emitExp(&addr);
                Value *valueexp = emitExp(&value);
                bool has_syncscope = attr.hasfield("syncscope");
                SyncScope::ID syncscope = ParseAtomicSyncScope(
                        M, has_syncscope ? attr.string("syncscope") : NULL);
                AtomicOrdering ordering = ParseAtomicOrdering(attr.string("ordering"));
                bool has_alignment = attr.hasfield("alignment");
#if LLVM_VERSION >= 130
                MaybeAlign alignment;
                if (has_alignment) {
                    alignment = MaybeAlign(attr.number("alignment"));
                }
#endif
                AtomicRMWInst *a = B->CreateAtomicRMW(op, addrexp, valueexp,
#if LLVM_VERSION >= 130
                                                      alignment,
#endif
                                                      ordering, syncscope);
                a->setVolatile(attr.boolean("isvolatile"));
                if (has_alignment) {
#if LLVM_VERSION < 130
                    a->setAlignment(Align(attr.number("alignment")));
#endif
                }
                return a;
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
        // should not be reachable - every case above should either return or assert
        return 0;
    }
    BasicBlock *createAndInsertBB(StringRef name) {
        return BasicBlock::Create(*CU->TT->ctx, name, fstate->func);
    }
    void followsBB(BasicBlock *b) { b->moveAfter(B->GetInsertBlock()); }
    Value *emitCond(Obj *cond) { return emitCond(emitExp(cond)); }
    Value *emitCond(Value *cond) {
        Type *resultType = Type::getInt1Ty(*CU->TT->ctx);
        if (cond->getType()->isVectorTy()) {
            VectorType *vt = cast<VectorType>(cond->getType());
#if LLVM_VERSION < 130
            resultType = VectorType::get(resultType, vt->getNumElements(), false);
#else
            resultType = VectorType::get(resultType,
                                         vt->getElementCount().getKnownMinValue(), false);
#endif
        }
        return B->CreateTrunc(cond, resultType);
    }

    llvm::ConstantInt *emitConstantInt(Obj *v) {
        return dyn_cast<llvm::ConstantInt>(emitExp(v));  // TODO: collapse constants
    }

    void emitIfBranch(Obj *ifbranch, BasicBlock *footer) {
        Obj cond, body;
        ifbranch->obj("condition", &cond);
        ifbranch->obj("body", &body);
        BasicBlock *thenBB = createAndInsertBB("then");
        BasicBlock *continueif = createAndInsertBB("else");
        emitBranchOnExpr(&cond, thenBB, continueif);

        setInsertBlock(thenBB);

        emitStmt(&body);
        B->CreateBr(footer);
        followsBB(continueif);
        setInsertBlock(continueif);
    }

    void emitCaseBranch(Obj *casebranch, SwitchInst *sw, BasicBlock *footer) {
        Obj caseindex, body;
        casebranch->obj("condition", &caseindex);
        casebranch->obj("body", &body);

        BasicBlock *thenBB = createAndInsertBB("then");
        sw->addCase(emitConstantInt(&caseindex), thenBB);
        followsBB(thenBB);
        setInsertBlock(thenBB);

        emitStmt(&body);
        B->CreateBr(footer);
    }

    DIFileP createDebugInfoForFile(const char *filename) {
        // checking the existence of a file once per function can be expensive,
        // so only do it if debug mode is set to slow compile anyway.
        // In the future, we can cache across functions calls if needed
        if (T->options.debug > 1 && llvm::sys::fs::exists(filename)) {
            SmallString<256> filepath = StringRef(filename);
            llvm::sys::fs::make_absolute(filepath);
            return DB->createFile(llvm::sys::path::filename(filepath),
                                  llvm::sys::path::parent_path(filepath));

        } else {
            return DB->createFile(filename, ".");
        }
    }
    MDNode *debugScopeForFile(const char *filename) {
        StringMap<MDNode *>::iterator it = filenamecache.find(filename);
        if (it != filenamecache.end()) return it->second;
        MDNode *block = DB->createLexicalBlockFile(SP, createDebugInfoForFile(filename));
        filenamecache[filename] = block;
        return block;
    }
    void initDebug(const char *filename, int lineno) {
        customfilename = NULL;
        customlinenumber = 0;
        DEBUG_ONLY(T) {
            DB = new DIBuilder(*M);

            DIFileP file = createDebugInfoForFile(filename);
            DICompileUnit *CU = DB->createCompileUnit(
                    dwarf::DW_LANG_C89, DB->createFile("compilationunit", "."), "terra",
                    true, "", 0);

            auto TA = DB->getOrCreateTypeArray(ArrayRef<Metadata *>());

            SP = DB->createFunction(
                    CU, fstate->func->getName(), fstate->func->getName(), file, lineno,
                    DB->createSubroutineType(TA), 0, llvm::DINode::FlagZero,
                    llvm::DISubprogram::DISPFlags::SPFlagOptimized |
                            llvm::DISubprogram::DISPFlags::SPFlagDefinition);
            fstate->func->setSubprogram(SP);

            if (!M->getModuleFlagsMetadata()) {
                M->addModuleFlag(llvm::Module::Warning, "Dwarf Version", 2);
                M->addModuleFlag(llvm::Module::Warning, "Debug Info Version", 1);

#ifdef _WIN32
                M->addModuleFlag(llvm::Module::Warning, "CodeView", 1);
                M->addModuleFlag(llvm::Module::Warning, "CodeViewGHash", 1);
#endif
            }
            filenamecache[filename] = SP;
        }
    }
    void endDebug() {
        DEBUG_ONLY(T) {
            DB->finalize();
            delete DB;
            DB = nullptr;
        }
    }
    void setDebugPoint(Obj *obj) {
        DEBUG_ONLY(T) {
            MDNode *scope = debugScopeForFile(customfilename ? customfilename
                                                             : obj->string("filename"));
#if LLVM_VERSION < 120
            B->SetCurrentDebugLocation(DebugLoc::get(
                    customfilename ? customlinenumber : obj->number("linenumber"), 0,
                    scope));
#else
            B->SetCurrentDebugLocation(DILocation::get(
                    scope->getContext(),
                    customfilename ? customlinenumber : obj->number("linenumber"), 0,
                    scope));
#endif
        }
    }

    void setInsertBlock(BasicBlock *bb) { B->SetInsertPoint(bb); }
    void pushBreakpoint(BasicBlock *exit) {
        breakpoints.push_back(std::make_pair(exit, deferred.size()));
    }
    void popBreakpoint() { breakpoints.pop_back(); }
    BasicBlock *getOrCreateBlockForLabel(Obj *stmt, int *depth) {
        Obj ident, lbl;
        stmt->obj("label", &ident);
        ident.obj("value", &lbl);
        BasicBlock *bb = lookupSymbol<BasicBlock>(labels, &lbl);
        if (!bb) {
            bb = createAndInsertBB(lbl.asstring("value"));
            mapSymbol(labels, &lbl, bb);
        }
        labeldepth->push();
        lbl.push();
        lua_gettable(L, -2);
        *depth = luaL_checknumber(L, -1);
        lua_pop(L, 2);
        return bb;
    }
    Value *emitCall(Obj *call, bool defer) {
        Obj paramlist;
        Obj paramtypes;
        Obj func;

        call->obj("arguments", &paramlist);
        paramlist.pushfield("map");  // call arguments:map("type") to get paramtypes
        paramlist.push();
        lua_pushstring(L, "type");
        lua_call(L, 2, 1);
        paramlist.fromStack(&paramtypes);

        call->obj("value", &func);

        CallingConv::ID callingconv = CallingConv::MaxID;
        if (func.hasfield("callingconv")) {
            callingconv = ParseCallingConv(func.string("callingconv"));
        }

        Value *fn = emitExp(&func);

        Obj fnptrtyp;
        func.obj("type", &fnptrtyp);
        Obj fntyp;
        fnptrtyp.obj("type", &fntyp);

        std::vector<Value *> actuals;
        emitExpressionList(&paramlist, true, &actuals);
        BasicBlock *cur = B->GetInsertBlock();
        if (defer) {
            BasicBlock *bb = createAndInsertBB("defer");
            setInsertBlock(bb);
            deferred.push_back(bb);
        }
        Value *r = CC->EmitCall(B, &fntyp, callingconv, &paramtypes, fn, &actuals);
        setInsertBlock(cur);  // defer may have changed it
        return r;
    }

    void emitReturnUndef() {
        Type *rt = fstate->func->getReturnType();
        if (rt->isVoidTy()) {
            B->CreateRetVoid();
        } else {
            B->CreateRet(UndefValue::get(rt));
        }
    }
    void emitExpressionList(Obj *exps, bool loadlvalue, std::vector<Value *> *results) {
        int N = exps->size();
        for (int i = 0; i < N; i++) {
            Obj exp;
            exps->objAt(i, &exp);
            results->push_back(emitExp(&exp, loadlvalue));
        }
    }
    Value *emitConstructor(Obj *exp, Obj *expressions) {
        Type *ttype = typeOfValue(exp)->type;
        Value *result = CreateAlloca(B, ttype);
        std::vector<Value *> values;
        emitExpressionList(expressions, true, &values);
        for (size_t i = 0; i < values.size(); i++) {
            Value *addr = CreateConstGEP2_32(B, result, ttype, 0, i);
            B->CreateStore(values[i], addr);
        }
        return B->CreateLoad(ttype, result);
    }
    void emitStmtList(Obj *stmts) {
        int NS = stmts->size();
        for (int i = 0; i < NS; i++) {
            Obj s;
            stmts->objAt(i, &s);
            emitStmt(&s);
        }
    }
    Value *emitLetIn(Obj *letin) {
        Obj stmts, exps;
        letin->obj("statements", &stmts);
        emitStmtList(&stmts);
        letin->obj("expressions", &exps);
        if (exps.size() == 1) {
            Obj exp;
            exps.objAt(0, &exp);
            return emitExp(&exp, false);
        }
        return emitConstructor(letin, &exps);
    }
    void startDeadCode() {
        BasicBlock *bb = createAndInsertBB("dead");
        setInsertBlock(bb);
    }
    BasicBlock *copyBlock(BasicBlock *BB) {
        ValueToValueMapTy VMap;
        DebugInfoFinder DIFinder;
        BasicBlock *NewBB =
                CloneBasicBlock(BB, VMap, "defer", fstate->func, nullptr, &DIFinder);
        VMap[BB] = NewBB;

        BasicBlock::iterator oldII = BB->begin();

        for (BasicBlock::iterator II = NewBB->begin(), IE = NewBB->end(); II != IE;
             ++II) {
            // HACK: LLVM is not happy about terra copying single isolated BasicBlocks,
            // and will blow up when copying metadata. This removes the metadata before
            // remapping, then copies it afterwards, which isn't fully correct, but works.
            llvm::SmallVector<std::pair<unsigned int, llvm::MDNode *>, 4> MDs;
            II->getAllMetadata(MDs);
            for (auto md : MDs) II->setMetadata(md.first, nullptr);

            RemapInstruction(&*II, VMap, RF_IgnoreMissingLocals);

            II->copyMetadata(*oldII);
            ++oldII;
        }
        return NewBB;
    }
    // emit an exit path that includes the most recent num deferred statements
    // this is used by gotos,returns, and breaks. unlike scope ends it copies the dtor
    // stack
    void emitDeferred(size_t num) {
        for (size_t i = 0; i < num; i++) {
            BasicBlock *bb = deferred[deferred.size() - 1 - i];
            bb = copyBlock(bb);
            B->CreateBr(bb);
            setInsertBlock(bb);
        }
    }
    // unwind deferred and remove them from dtor stack, no need to copy the BB, since this
    // is its last use
    void unwindDeferred(size_t to) {
        for (; deferred.size() > to; deferred.pop_back()) {
            BasicBlock *bb = deferred.back();
            B->CreateBr(bb);
            setInsertBlock(bb);
        }
    }
    void enterScope(Locals *buf) {
        buf->prev = locals;
        newMap(&buf->cur);
        locals = buf;
    }
    void leaveScope() {
        assert(locals);
        locals = locals->prev;
    }
    void emitStmt(Obj *stmt) {
        setDebugPoint(stmt);
        T_Kind kind = stmt->kind("kind");
        switch (kind) {
            case T_block: {
                Locals buf;
                enterScope(&buf);
                size_t N = deferred.size();
                Obj stmts;
                stmt->obj("statements", &stmts);
                emitStmtList(&stmts);
                unwindDeferred(N);
                leaveScope();
            } break;
            case T_returnstat: {
                Obj exp;
                stmt->obj("expression", &exp);
                Value *result = emitExp(&exp);
                ;
                Obj ftype;
                funcobj->obj("type", &ftype);
                emitDeferred(deferred.size());
                CC->EmitReturn(B, &ftype, fstate->func, result);
                startDeadCode();
            } break;
            case T_label: {
                int depth;
                BasicBlock *bb = getOrCreateBlockForLabel(stmt, &depth);
                assert((size_t)depth == deferred.size());
                B->CreateBr(bb);
                followsBB(bb);
                setInsertBlock(bb);
            } break;
            case T_gotostat: {
                int depth;
                BasicBlock *bb = getOrCreateBlockForLabel(stmt, &depth);
                assert(deferred.size() >= (size_t)depth);
                emitDeferred(deferred.size() - depth);
                B->CreateBr(bb);
                startDeadCode();
            } break;
            case T_breakstat: {
                Obj def;
                auto breakpoint = breakpoints.back();
                assert(breakpoints.size() > 0);
                emitDeferred(deferred.size() - breakpoint.second);
                B->CreateBr(breakpoint.first);
                startDeadCode();
            } break;
            case T_whilestat: {
                Obj cond, body;
                stmt->obj("condition", &cond);
                stmt->obj("body", &body);
                BasicBlock *condBB = createAndInsertBB("condition");

                B->CreateBr(condBB);
                setInsertBlock(condBB);

                BasicBlock *loopBody = createAndInsertBB("whilebody");
                BasicBlock *merge = createAndInsertBB("merge");

                pushBreakpoint(merge);

                emitBranchOnExpr(&cond, loopBody, merge);
                setInsertBlock(loopBody);
                emitStmt(&body);

                B->CreateBr(condBB);

                followsBB(merge);
                setInsertBlock(merge);
                popBreakpoint();

            } break;
            case T_fornum: {
                Obj initial, step, limit, variable, body;
                stmt->obj("initial", &initial);
                bool hasstep = stmt->obj("step", &step);
                stmt->obj("limit", &limit);
                stmt->obj("variable", &variable);
                stmt->obj("body", &body);
                TType *t = typeOfValue(&variable);
                Value *initialv = emitExp(&initial);
                Value *limitv = emitExp(&limit);
                Value *stepv = (hasstep) ? emitExp(&step) : ConstantInt::get(t->type, 1);
                Value *vp = emitExp(&variable, false);
                Value *zero = ConstantInt::get(t->type, 0);
                B->CreateStore(initialv, vp);
                BasicBlock *cond = createAndInsertBB("forcond");
                B->CreateBr(cond);
                setInsertBlock(cond);
                Value *v = B->CreateLoad(t->type, vp);
                Value *c = B->CreateOr(B->CreateAnd(emitCompare(T_lt, t, v, limitv),
                                                    emitCompare(T_gt, t, stepv, zero)),
                                       B->CreateAnd(emitCompare(T_gt, t, v, limitv),
                                                    emitCompare(T_le, t, stepv, zero)));
                BasicBlock *loopBody = createAndInsertBB("forbody");
                BasicBlock *merge = createAndInsertBB("merge");
                pushBreakpoint(merge);
                B->CreateCondBr(c, loopBody, merge);
                setInsertBlock(loopBody);
                emitStmt(&body);
                B->CreateStore(B->CreateAdd(v, stepv), vp);
                B->CreateBr(cond);
                followsBB(merge);
                setInsertBlock(merge);

                popBreakpoint();
            } break;
            case T_ifstat: {
                Obj branches;
                stmt->obj("branches", &branches);
                int N = branches.size();
                BasicBlock *footer = createAndInsertBB("merge");
                for (int i = 0; i < N; i++) {
                    Obj branch;
                    branches.objAt(i, &branch);
                    emitIfBranch(&branch, footer);
                }
                Obj orelse;
                if (stmt->obj("orelse", &orelse)) emitStmt(&orelse);
                B->CreateBr(footer);
                followsBB(footer);
                setInsertBlock(footer);
            } break;
            case T_switchstat: {
                Obj cond;
                stmt->obj("condition", &cond);

                BasicBlock *footer = createAndInsertBB("merge");
                BasicBlock *dest = createAndInsertBB("default_block");
                Value *condexpr = emitExp(&cond);
                Obj cases;
                stmt->obj("cases", &cases);
                int N = cases.size();
                SwitchInst *sw = B->CreateSwitch(condexpr, dest, N);
                for (int i = 0; i < N; i++) {
                    Obj casebranch;
                    cases.objAt(i, &casebranch);
                    emitCaseBranch(&casebranch, sw, footer);
                }
                followsBB(dest);
                setInsertBlock(dest);

                Obj ordefault;
                if (stmt->obj("ordefault", &ordefault)) emitStmt(&ordefault);
                B->CreateBr(footer);
                followsBB(footer);
                setInsertBlock(footer);
            } break;
            case T_repeatstat: {
                Obj cond, statements;
                stmt->obj("condition", &cond);
                stmt->obj("statements", &statements);

                BasicBlock *loopBody = createAndInsertBB("repeatbody");
                BasicBlock *merge = createAndInsertBB("merge");

                pushBreakpoint(merge);

                B->CreateBr(loopBody);
                setInsertBlock(loopBody);
                size_t N = deferred.size();
                emitStmtList(&statements);
                if (N <
                    deferred.size()) {  // because the body and the conditional are in
                                        // the same block scope we need special
                                        // handling for deferred along the back edge of
                                        // the loop we must emit the deferred blocks
                    BasicBlock *backedge = createAndInsertBB("repeatdeferred");
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

                popBreakpoint();
            } break;
            case T_assignment: {
                std::vector<Value *> rhsexps;
                Obj rhss;
                stmt->obj("rhs", &rhss);
                emitExpressionList(&rhss, true, &rhsexps);
                Obj lhss;
                stmt->obj("lhs", &lhss);
                int N = lhss.size();
                for (int i = 0; i < N; i++) {
                    Obj lhs;
                    lhss.objAt(i, &lhs);
                    if (lhs.kind("kind") == T_setter) {
                        Obj rhsvar, setter;
                        lhs.obj("rhs", &rhsvar);
                        lhs.obj("setter", &setter);
                        Value *rhsvarV = emitExp(&rhsvar, false);
                        B->CreateStore(rhsexps[i], rhsvarV);
                        emitExp(&setter);
                    } else {
                        emitStore(rhsexps[i], emitExp(&lhs, false),
                                  /* isVolatile */ false, MaybeAlign());
                    }
                }
            } break;
            case T_defer: {
                Obj expression;
                stmt->obj("expression", &expression);
                emitCall(&expression, true);
            } break;
            default: {
                emitExp(stmt, false);
            } break;
        }
    }
};

static Constant *EmitConstantInitializer(TerraCompilationUnit *CU, Obj *v) {
    FunctionEmitter fe(CU);
    return fe.emitConstantExpression(v);
}

Function *EmitFunction(TerraCompilationUnit *CU, Obj *funcdecl,
                       TerraFunctionState *user) {
    Obj funcdefn;
    funcdecl->obj("definition", &funcdefn);
    FunctionEmitter fe(CU);
    TerraFunctionState *result = fe.emitFunction(&funcdefn);
    if (user && result->onstack)
        user->lowlink =
                std::min(user->lowlink, result->lowlink);  // Tarjan's scc algorithm

    return result->func;
}

static int terra_compilationunitaddvalue(
        lua_State *L) {  // entry point into compiler from lua code
    terra_State *T = terra_getstate(L, 1);
    GlobalValue *gv;
    // create lua table to hold object references anchored on stack
    int ref_table = lobj_newreftable(T->L);
    {
        Obj cu, globals, value;
        lua_pushvalue(L, COMPILATION_UNIT_POS);  // the compilation unit
        cu.initFromStack(L, ref_table);
        cu.obj("symbols", &globals);
        const char *modulename = (lua_isnil(L, 2)) ? NULL : lua_tostring(L, 2);
        lua_pushvalue(L, 3);  // the function definition
        cu.fromStack(&value);
        TerraCompilationUnit *CU = (TerraCompilationUnit *)cu.cd("llvm_cu");
        assert(CU);

        Types Ty(CU);
        CCallingConv CC(CU, &Ty);
        std::vector<TerraFunctionState *> tooptimize;
        CU->Ty = &Ty;
        CU->CC = &CC;
        CU->symbols = &globals;
        CU->tooptimize = &tooptimize;
        if (value.kind("kind") == T_globalvariable) {
            gv = EmitGlobalVariable(CU, &value, "anon");
        } else {
            gv = EmitFunction(CU, &value, NULL);
        }
        gv->setLinkage(
                GlobalValue::ExternalLinkage);  // User explicitly exported this function.
        CU->Ty = NULL;
        CU->CC = NULL;
        CU->symbols = NULL;
        CU->tooptimize = NULL;
        if (modulename) {
            if (GlobalValue *gv2 = CU->M->getNamedValue(modulename))
                gv2->setName(
                        Twine(StringRef(modulename),
                              "_renamed"));  // rename anything else that has this name
            gv->setName(modulename);         // and set our function to this name
            assert(gv->getName() == modulename);  // make sure it worked
        }
        // cleanup -- ensure we left the stack the way we started
        assert(lua_gettop(T->L) == ref_table);
    }  // scope to ensure that all Obj held in the compiler are destroyed before we pop
       // the reference table off the stack
    lobj_removereftable(T->L, ref_table);
    lua_pushlightuserdata(L, gv);
    return 1;
}

static int terra_llvmsizeof(lua_State *L) {
    terra_State *T = terra_getstate(L, 1);
    int ref_table = lobj_newreftable(L);
    TType *llvmtyp;
    TerraCompilationUnit *CU;
    {
        Obj cu, typ, globals;
        lua_pushvalue(L, 1);
        cu.initFromStack(L, ref_table);
        lua_pushvalue(L, 2);
        typ.initFromStack(L, ref_table);
        cu.obj("symbols", &globals);
        CU = (TerraCompilationUnit *)cu.cd("llvm_cu");
        CU->symbols = &globals;
        llvmtyp = Types(CU).Get(&typ);
        CU->symbols = NULL;
    }
    lobj_removereftable(T->L, ref_table);
    lua_pushnumber(T->L, CU->getDataLayout().getTypeAllocSize(llvmtyp->type));
    return 1;
}

static void *GetGlobalValueAddress(TerraCompilationUnit *CU, StringRef Name) {
    if (CU->T->options.debug > 1)
        return sys::DynamicLibrary::SearchForAddressOfSymbol(Name.str());

    return (void *)CU->ee->getGlobalValueAddress(Name.str());
}
static bool MCJITShouldCopy(GlobalValue *G, void *data) {
    TerraCompilationUnit *CU = (TerraCompilationUnit *)data;
    if (dyn_cast<Function>(G) != NULL || dyn_cast<GlobalVariable>(G) != NULL)
        return 0 == GetGlobalValueAddress(CU, G->getName());
    return true;
}

static bool SaveSharedObject(TerraCompilationUnit *CU, Module *M,
                             std::vector<const char *> *args, const char *filename);

static void *JITGlobalValue(TerraCompilationUnit *CU, GlobalValue *gv) {
    InitializeJIT(CU);
    ExecutionEngine *ee = CU->ee;
    if (gv->isDeclaration()) {
        StringRef name = gv->getName();
        if (name.startswith("\01"))  // remove asm renaming tag before looking for symbol
            name = name.substr(1);
        return ee->getPointerToNamedFunction(name);
    }
    void *ptr = GetGlobalValueAddress(CU, gv->getName());
    if (ptr) {
        return ptr;
    }
    llvm::ValueToValueMapTy VMap;
    Module *m = llvmutil_extractmodulewithproperties(gv->getName(), gv->getParent(), &gv,
                                                     1, MCJITShouldCopy, CU, VMap);

    if (CU->T->options.debug > 1) {
        llvm::SmallString<256> tmpname;
        llvmutil_createtemporaryfile("terra", "so", tmpname);
        if (SaveSharedObject(CU, m, NULL, tmpname.c_str())) lua_error(CU->T->L);
        sys::DynamicLibrary::LoadLibraryPermanently(tmpname.c_str());
        void *result = sys::DynamicLibrary::SearchForAddressOfSymbol(gv->getName().str());
        assert(result);
        return result;
    }
    ee->addModule(UNIQUEIFY(Module, m));
    return (void *)ee->getGlobalValueAddress(gv->getName().str());
}

static int terra_jit(lua_State *L) {
    terra_getstate(L, 1);
    TerraCompilationUnit *CU = (TerraCompilationUnit *)terra_tocdatapointer(L, 1);
    GlobalValue *gv = (GlobalValue *)lua_touserdata(L, 2);
    double begin = CurrentTimeInSeconds();
    void *ptr = JITGlobalValue(CU, gv);
    double t = CurrentTimeInSeconds() - begin;
    lua_pushlightuserdata(L, ptr);
    lua_pushnumber(L, t);
    return 2;
}

static int terra_deletefunction(lua_State *L) {
    TerraCompilationUnit *CU =
            (TerraCompilationUnit *)terra_tocdatapointer(L, lua_upvalueindex(1));
    TerraFunctionState *fstate = (TerraFunctionState *)lua_touserdata(L, -1);
    assert(fstate);
    Function *func = fstate->func;
    assert(func);
    VERBOSE_ONLY(CU->T) {
        printf("deleting function: %s\n", func->getName().str().c_str());
    }
    // MCJIT can't free individual functions, so we need to leak the generated code

    // for MCJIT, we need to keep the declaration so
    // another function doesn't get the same name
    VERBOSE_ONLY(CU->T) {
        printf("... uses not empty, removing body but keeping declaration.\n");
    }
    func->deleteBody();
    VERBOSE_ONLY(CU->T) { printf("... finish delete.\n"); }
    fstate->func = NULL;
    freecompilationunit(CU);
    return 0;
}
static int terra_disassemble(lua_State *L) {
    terra_State *T = terra_getstate(L, 1);
    Function *fn = (Function *)lua_touserdata(L, 1);
    assert(fn);
    void *addr = lua_touserdata(L, 2);
    assert(fn);
    TERRA_DUMP_FUNCTION(fn);
    if (T->C->functioninfo.count(addr)) {
        TerraFunctionInfo &fi = T->C->functioninfo[addr];
        printf("assembly for function at address %p\n", addr);
        llvmutil_disassemblefunction(fi.addr, fi.size, 0);
    }
    return 0;
}

static bool FindLinker(terra_State *T, LLVM_PATH_TYPE *linker, const char *target) {
#ifndef _WIN32
    const char *linker_name = getenv("CC");
    if (!linker_name) linker_name = getenv("CXX");
    if (!linker_name) linker_name = "gcc";
    *linker = *sys::findProgramByName(linker_name);
    return *linker == "";
#else
    lua_getfield(T->L, LUA_GLOBALSINDEX, "terra");
    lua_getfield(T->L, -1, "getvclinker");
    lua_pushstring(T->L, target);
    lua_call(T->L, 1, 3);
    *linker = LLVM_PATH_TYPE(lua_tostring(T->L, -3));
    const char *vclib = lua_tostring(T->L, -2);
    const char *vcpath = lua_tostring(T->L, -1);
    _putenv(vclib);
    _putenv(vcpath);
    lua_pop(T->L, 4);
    return false;
#endif
}

static bool SaveAndLink(TerraCompilationUnit *CU, Module *M,
                        std::vector<const char *> *linkargs, const char *filename) {
    llvm::SmallString<256> tmpname;
    llvmutil_createtemporaryfile("terra", "o", tmpname);
    const char *tmpnamebuf = tmpname.c_str();
    FD_ERRTYPE err;
    raw_fd_ostream tmp(tmpnamebuf, err, RAW_FD_OSTREAM_BINARY);
    if (FD_ISERR(err)) {
        terra_pusherror(CU->T, "llvm: %s", FD_ERRSTR(err));
        unlink(tmpnamebuf);
        return true;
    }
    if (llvmutil_emitobjfile(M, CU->TT->tm, true, tmp)) {
        terra_pusherror(CU->T, "llvm: llvmutil_emitobjfile");
        unlink(tmpnamebuf);
        return true;
    }
    tmp.close();
    LLVM_PATH_TYPE linker;
    std::string arch(CU->TT->Triple);
    arch.erase(arch.find_first_of('-'));
    if (FindLinker(CU->T, &linker, arch.c_str())) {
        unlink(tmpnamebuf);
        terra_pusherror(CU->T, "llvm: failed to find linker");
        return true;
    }
    std::vector<const char *> cmd;
    cmd.push_back(linker.c_str());
    cmd.push_back(tmpnamebuf);
    if (linkargs) cmd.insert(cmd.end(), linkargs->begin(), linkargs->end());

#ifndef _WIN32
    cmd.push_back("-o");
    cmd.push_back(filename);
#else
    cmd.push_back("-defaultlib:msvcrt");
    cmd.push_back("-nologo");
    llvm::SmallString<256> fileout("-out:");
    fileout.append(filename);
    cmd.push_back(fileout.c_str());
#endif

    cmd.push_back(NULL);
    std::string errstr;
    if (llvmutil_executeandwait(linker, &cmd[0], &errstr)) {
        unlink(tmpnamebuf);
        unlink(filename);
        terra_pusherror(CU->T, "llvm: %s\n", errstr.c_str());
        return true;
    }
    return false;
}

static bool SaveObject(TerraCompilationUnit *CU, Module *M, const std::string &filekind,
                       emitobjfile_t &dest) {
    if (filekind == "object" || filekind == "asm") {
        if (llvmutil_emitobjfile(M, CU->TT->tm, filekind == "object", dest)) {
            terra_pusherror(CU->T, "llvm: llvmutil_emitobjfile");
            return true;
        }
    } else if (filekind == "bitcode") {
        llvm::WriteBitcodeToFile(*M, dest);
    } else if (filekind == "llvmir") {
        dest << *M;
    }
    return false;
}
static bool SaveSharedObject(TerraCompilationUnit *CU, Module *M,
                             std::vector<const char *> *args, const char *filename) {
    std::vector<const char *> cmd;
#ifdef __APPLE__
    cmd.push_back("-g");
    cmd.push_back("-dynamiclib");
    cmd.push_back("-single_module");
    cmd.push_back("-undefined");
    cmd.push_back("dynamic_lookup");
    cmd.push_back("-fPIC");
#elif _WIN32
    cmd.push_back("-dll");
#else
    cmd.push_back("-g");
    cmd.push_back("-shared");
    cmd.push_back("-Wl,-export-dynamic");
#ifndef __FreeBSD__
    cmd.push_back("-ldl");
#endif
    cmd.push_back("-fPIC");
#endif

    if (args) cmd.insert(cmd.end(), args->begin(), args->end());
    return SaveAndLink(CU, M, &cmd, filename);
}

static int terra_saveobjimpl(lua_State *L) {
    terra_State *T = terra_getstate(L, 1);

    const char *filename = lua_tostring(L, 1);  // NULL means write to memory
    std::string filekind = lua_tostring(L, 2);
    int argument_index = 4;
    bool optimize = lua_toboolean(L, 5);

    lua_getfield(L, 3, "llvm_cu");
    TerraCompilationUnit *CU = (TerraCompilationUnit *)terra_tocdatapointer(L, -1);
    assert(CU);
    if (optimize) {
        llvmutil_optimizemodule(CU->M, CU->TT->tm);
    }
    // TODO: interialize the non-exported functions?
    std::vector<const char *> args;
    int nargs = lua_objlen(L, argument_index);
    for (int i = 1; i <= nargs; i++) {
        lua_rawgeti(L, argument_index, i);
        args.push_back(luaL_checkstring(L, -1));
        lua_pop(L, 1);
    }

    bool result = false;
    int N = 0;

    if (filekind == "executable") {
        result = SaveAndLink(CU, CU->M, &args, filename);
    } else if (filekind == "sharedlibrary") {
        result = SaveSharedObject(CU, CU->M, &args, filename);
    } else {
        if (filename != NULL) {
            FD_ERRTYPE err;
            raw_fd_ostream dest(
                    filename, err,
                    (filekind == "llvmir") ? RAW_FD_OSTREAM_NONE : RAW_FD_OSTREAM_BINARY);
            if (FD_ISERR(err)) {
                terra_pusherror(T, "llvm: %s", FD_ERRSTR(err));
                result = true;
            } else {
                result = SaveObject(CU, CU->M, filekind, dest);
            }
        } else {
            SmallVector<char, 256> mem;
            {  // ensure stream is finished before we add the memory to lua
                raw_svector_ostream dest(mem);
                result = SaveObject(CU, CU->M, filekind, dest);
            }
            N = 1;
            lua_pushlstring(L, &mem[0], mem.size());
        }
    }
    if (result) lua_error(CU->T->L);

    return N;
}

static int terra_pointertolightuserdata(lua_State *L) {
    lua_pushlightuserdata(L, terra_tocdatapointer(L, -1));
    return 1;
}
static int terra_bindtoluaapi(lua_State *L) {
    int N = lua_gettop(L);
    assert(N >= 1);
    void *const *fn = (void *const *)lua_topointer(L, 1);
    assert(fn);
    lua_pushcclosure(L, (lua_CFunction)*fn, N - 1);
    return 1;
}
#if _MSC_VER < 1900 && defined(_WIN32)
#define ISFINITE(v) _finite(v)
#else
#define ISFINITE(v) std::isfinite(v)
#endif
static int terra_isintegral(lua_State *L) {
    double v = luaL_checknumber(L, -1);
    bool integral = ISFINITE(v) && (double)(int)v == v;
    lua_pushboolean(L, integral);
    return 1;
}
static int terra_linklibraryimpl(lua_State *L) {
    terra_State *T = terra_getstate(L, 1);
    std::string Err;
    if (sys::DynamicLibrary::LoadLibraryPermanently(luaL_checkstring(L, 1), &Err)) {
        terra_reporterror(T, "llvm: %s\n", Err.c_str());
    }
    return 0;
}
static int terra_linkllvmimpl(lua_State *L) {
    terra_State *T = terra_getstate(L, 1);
    (void)T;
    std::string Err;
    TerraTarget *TT = (TerraTarget *)terra_tocdatapointer(L, 1);
    size_t length;
    const char *filename = lua_tolstring(L, 2, &length);
    bool fromstring = lua_toboolean(L, 3);
    ErrorOr<std::unique_ptr<MemoryBuffer> > mb = std::error_code();
    if (fromstring) {
        std::unique_ptr<MemoryBuffer> mbcontents(
                MemoryBuffer::getMemBuffer(StringRef(filename, length), "", false));
        mb = std::move(mbcontents);
    } else {
        mb = MemoryBuffer::getFile(filename);
    }
    if (!mb) {
        if (fromstring)
            terra_reporterror(T, "linkllvm: %s\n", mb.getError().message().c_str());
        else
            terra_reporterror(T, "linkllvm(%s): %s\n", filename,
                              mb.getError().message().c_str());
    }
    Expected<std::unique_ptr<Module> > mm =
            parseBitcodeFile(mb.get()->getMemBufferRef(), *TT->ctx);
    if (!mm) {
        if (fromstring) {
            std::string Msg;
            raw_string_ostream S((Msg));
            logAllUnhandledErrors(mm.takeError(), S, "");
            S.flush();
            terra_reporterror(T, "linkllvm: %s\n", S.str().c_str());
        } else {
            std::string Msg;
            raw_string_ostream S((Msg));
            logAllUnhandledErrors(mm.takeError(), S, "");
            S.flush();
            terra_reporterror(T, "linkllvm(%s): %s\n", filename, S.str().c_str());
        }
    }
    Module *M = mm.get().release();
    M->setTargetTriple(TT->Triple);
    if (LLVMLinkModules2(llvm::wrap(TT->external), llvm::wrap(M))) {
        if (fromstring)
            terra_pusherror(T, "linker reported error");
        else
            terra_pusherror(T, "linker reported error on %s", filename);
        lua_error(T->L);
    }
    return 0;
}

static int terra_dumpmodule(lua_State *L) {
    terra_State *T = terra_getstate(L, 1);
    (void)T;
    TerraCompilationUnit *CU = (TerraCompilationUnit *)terra_tocdatapointer(L, 1);
    if (CU) TERRA_DUMP_MODULE(CU->M);
    return 0;
}
