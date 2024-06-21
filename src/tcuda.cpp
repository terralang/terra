/* See Copyright Notice in ../LICENSE.txt */

#include "tcuda.h"
#ifdef TERRA_ENABLE_CUDA

extern "C" {
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
}

#include <vector>

#include "cuda.h"
#include "cuda_runtime.h"
#include "nvvm.h"
#include "llvmheaders.h"
#include "terrastate.h"
#include "tcompilerstate.h"
#include "tllvmutil.h"
#include "tobj.h"
#include "cudalib.h"
#include <fstream>
#include <sstream>
#ifndef _WIN32
#include <unistd.h>
#endif

#define CUDA_DO2(err, str, ...)                                                    \
    do {                                                                           \
        int e = err;                                                               \
        if (e != CUDA_SUCCESS) {                                                   \
            terra_reporterror(T, "%s:%d: %s cuda reported error %d" str, __FILE__, \
                              __LINE__, #err, e, __VA_ARGS__);                     \
        }                                                                          \
    } while (0)

#define CUDA_DO(err) CUDA_DO2(err, "%s", "")

#define CUDA_SYM(_)              \
    _(nvvmAddModuleToProgram)    \
    _(nvvmCompileProgram)        \
    _(nvvmCreateProgram)         \
    _(nvvmGetCompiledResult)     \
    _(nvvmGetCompiledResultSize) \
    _(nvvmGetProgramLog)         \
    _(nvvmGetProgramLogSize)     \
    _(nvvmVersion)

struct terra_CUDAState {
    int initialized;
#define INIT_SYM(x) decltype(&::x) x;
    CUDA_SYM(INIT_SYM)
#undef INIT_SYM
};

void initializeNVVMState(terra_State *T) {
    if (!T->cuda->initialized) {
// dynamically assign all of our symbols
#define INIT_SYM(x)                                                                     \
    T->cuda->x = (decltype(&x))llvm::sys::DynamicLibrary::SearchForAddressOfSymbol(#x); \
    assert(T->cuda->x);
        CUDA_SYM(INIT_SYM)
#undef INIT_SYM
        T->cuda->initialized = 1;
    }
}

static void annotateKernel(terra_State *T, llvm::Module *M, llvm::Function *kernel,
                           const char *name, int value) {
    llvm::LLVMContext &ctx = M->getContext();
    std::vector<METADATA_ROOT_TYPE *> vals;
    llvm::NamedMDNode *annot = M->getOrInsertNamedMetadata("nvvm.annotations");
    llvm::MDString *str = llvm::MDString::get(ctx, name);
    vals.push_back(llvm::ValueAsMetadata::get(kernel));
    vals.push_back(str);
    vals.push_back(llvm::ConstantAsMetadata::get(
            llvm::ConstantInt::get(llvm::Type::getInt32Ty(ctx), value)));
    llvm::MDNode *node = llvm::MDNode::get(ctx, vals);
    annot->addOperand(node);
}

static const char *cudadatalayout =
        "e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-"
        "v16:16:16-v32:32:32-v64:64:64-v128:128:128-n16:32:64";

void moduleToPTX(terra_State *T, llvm::Module *M, int major, int minor, std::string *buf,
                 const char *libdevice) {
    int nmajor, nminor;
    CUDA_DO(T->cuda->nvvmVersion(&nmajor, &nminor));
    int nversion = nmajor * 10 + nminor;
    if (nversion >= 12)
        M->setTargetTriple("nvptx64-nvidia-cuda");
    else
        M->setTargetTriple("");  // clear these because nvvm doesn't like them
    M->setDataLayout("");        // nvvm doesn't like data layout either

    std::stringstream cpu;
    cpu << "sm_" << major << minor;
    std::string cpuopt = cpu.str();

    auto Features = "";

    std::string Error;
    auto Target = llvm::TargetRegistry::lookupTarget("nvptx64-nvidia-cuda", Error);

    // Print an error and exit if we couldn't find the requested target.
    // This generally occurs if we've forgotten to initialise the
    // TargetRegistry or we have a bogus target triple.
    if (!Target) {
        llvm::errs() << Error;
        return;
    }

    llvm::SmallString<2048> ErrMsg;
    auto MB = llvm::MemoryBuffer::getFile(libdevice);
    auto E_LDEVICE =
            llvm::parseBitcodeFile(MB->get()->getMemBufferRef(), M->getContext());

    if (auto Err = E_LDEVICE.takeError()) {
        llvm::logAllUnhandledErrors(std::move(Err), llvm::errs(), "[CUDA Error] ");
        return;
    }

    auto &LDEVICE = *E_LDEVICE;

    llvm::TargetOptions opt;
#if LLVM_VERSION < 170
    auto RM = llvm::Optional<llvm::Reloc::Model>();
#else
    std::optional<llvm::Reloc::Model> RM = std::nullopt;
#endif
    auto TargetMachine =
            Target->createTargetMachine("nvptx64-nvidia-cuda", cpuopt, Features, opt, RM);

    LDEVICE->setTargetTriple("nvptx64-nvidia-cuda");
    LDEVICE->setDataLayout(TargetMachine->createDataLayout());

    llvm::Linker Linker(*M);
    Linker.linkInModule(std::move(LDEVICE));

    M->setDataLayout(TargetMachine->createDataLayout());

    llvm::SmallString<2048> dest;
    llvm::raw_svector_ostream str_dest(dest);

#if LLVM_VERSION < 170
    llvm::PassManagerBuilder PMB;
    PMB.OptLevel = 3;
    PMB.SizeLevel = 0;
    PMB.Inliner = llvm::createFunctionInliningPass(PMB.OptLevel, 0, false);
    PMB.LoopVectorize = false;
#endif
    auto FileType =
#if LLVM_VERSION < 180
            llvm::CGFT_AssemblyFile
#else
            llvm::CodeGenFileType::AssemblyFile
#endif
            ;

    llvm::legacy::PassManager PM;
#if LLVM_VERSION < 160
    TargetMachine->adjustPassManager(PMB);
#endif

#if LLVM_VERSION < 170
    PMB.populateModulePassManager(PM);
#else
    M->setDataLayout(TargetMachine->createDataLayout());
#endif

    if (TargetMachine->addPassesToEmitFile(PM, str_dest, nullptr, FileType)) {
        llvm::errs() << "TargetMachine can't emit a file of this type\n";
        return;
    }

    PM.run(*M);
    buf->resize(dest.size());

    // {
    // 	std::stringstream outs;
    // 	outs << dest.size() << std::endl;
    // 	printf("[CUDA] Result size: %s\n", outs.str().c_str());
    // }

    (*buf) = dest.str().str();
}

// cuda doesn't like llvm generic names, so we replace non-identifier symbols here
static std::string sanitizeName(std::string name) {
    std::string s;
    llvm::raw_string_ostream out(s);
    for (size_t i = 0; i < name.size(); i++) {
        char c = name[i];
        if (isalnum(c) || c == '_')
            out << c;
        else
            out << "_$" << (int)c << "_";
    }
    out.flush();
    return s;
}

int terra_toptx(lua_State *L) {
    terra_State *T = terra_getstate(L, 1);
    initializeNVVMState(T);
    lua_getfield(L, 1, "llvm_cu");
    TerraCompilationUnit *CU = (TerraCompilationUnit *)terra_tocdatapointer(L, -1);
    llvm::Module *M = CU->M;
    int annotations = 2;
    int dumpmodule = lua_toboolean(L, 3);
    int version = lua_tonumber(L, 4);
    int major = version / 10;
    int minor = version % 10;
    const char *libdevice = lua_tostring(L, 5);

    int N = lua_objlen(L, annotations);
    for (int i = 0; i < N; i++) {
        lua_rawgeti(L, annotations, i + 1);  // {kernel,annotation,value}
        lua_rawgeti(L, -1, 1);               // kernel name
        lua_rawgeti(L, -2, 2);               // annotation name
        lua_rawgeti(L, -3, 3);               // annotation value
        const char *kernelname = luaL_checkstring(L, -3);
        const char *annotationname = luaL_checkstring(L, -2);
        int annotationvalue = luaL_checkint(L, -1);
        llvm::Function *kernel = M->getFunction(kernelname);
        assert(kernel);
        annotateKernel(T, M, kernel, annotationname, annotationvalue);
        lua_pop(L, 4);  // annotation table and 3 values in it
    }

    // sanitize names
    for (llvm::Module::iterator it = M->begin(), end = M->end(); it != end; ++it) {
        const char *prefix = "cudart:";
        size_t prefixsize = strlen(prefix);
        std::string name = it->getName().str();
        if (name.size() >= prefixsize && name.substr(0, prefixsize) == prefix) {
            std::string shortname = name.substr(prefixsize);
            it->setName(shortname);
        }
        if (!it->isDeclaration()) {
            it->setName(sanitizeName(it->getName().str()));
        }
    }
    for (llvm::Module::global_iterator it = M->global_begin(), end = M->global_end();
         it != end; ++it) {
        it->setName(sanitizeName(it->getName().str()));
    }

    std::string ptx;
    moduleToPTX(T, M, major, minor, &ptx, libdevice);
    if (dumpmodule) {
        fprintf(stderr, "CUDA Module:\n");
        M->print(llvm::errs(), nullptr);
        fprintf(stderr, "Generated PTX:\n%s\n", ptx.c_str());
    }
    lua_pushstring(L, ptx.c_str());
    return 1;
}

int terra_cudainit(struct terra_State *T) {
    lua_getfield(T->L, LUA_GLOBALSINDEX, "terra");
    lua_getfield(T->L, -1, "cudalibpaths");
    lua_getfield(T->L, -1, "nvvm");
    const char *libnvvmpath = lua_tostring(T->L, -1);
    lua_pop(T->L, 2);  // path and cudalibpaths
    if (llvm::sys::DynamicLibrary::LoadLibraryPermanently(libnvvmpath)) {
        llvm::SmallString<256> err;
        err.append("failed to load libnvvm at: ");
        err.append(libnvvmpath);
        lua_pushstring(T->L, err.c_str());
        lua_setfield(T->L, -2, "cudaloaderror");
        lua_pop(T->L, 1);  // terralib
        return 0;          // couldn't find the libnvvm library, do not load cudalib.lua
    }
    T->cuda = (terra_CUDAState *)malloc(sizeof(terra_CUDAState));
    T->cuda->initialized =
            0; /* actual CUDA initalization is done on first call to terra_cudacompile */
               /* this function just registers all the Lua state associated with CUDA */

    lua_pushlightuserdata(T->L, (void *)T);
    lua_pushcclosure(T->L, terra_toptx, 1);
    lua_setfield(T->L, -2, "toptximpl");
    lua_pop(T->L, 1);  // terralib
    int err = terra_loadandrunbytecodes(T->L, (const unsigned char *)luaJIT_BC_cudalib,
                                        luaJIT_BC_cudalib_SIZE, "cudalib.lua");
    if (err) {
        return err;
    }
    return 0;
}

#else
/* cuda disabled, just do nothing */
int terra_cudainit(struct terra_State* T) { return 0; }
#endif

int terra_cudafree(struct terra_State *T) {
    // currently nothing to clean up
    return 0;
}
