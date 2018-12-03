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


#define CUDA_DO2(err,str,...) do { \
    int e = err; \
    if(e != CUDA_SUCCESS) { \
        terra_reporterror(T,"%s:%d: %s cuda reported error %d" str,__FILE__,__LINE__,#err,e,__VA_ARGS__); \
    } \
} while(0)

#define CUDA_DO(err) CUDA_DO2(err,"%s","")

#define CUDA_SYM(_) \
    _(nvvmAddModuleToProgram) \
    _(nvvmCompileProgram) \
    _(nvvmCreateProgram) \
    _(nvvmGetCompiledResult) \
    _(nvvmGetCompiledResultSize) \
    _(nvvmGetProgramLog) \
    _(nvvmGetProgramLogSize) \
    _(nvvmVersion)

struct terra_CUDAState {
    int initialized;
    #define INIT_SYM(x) decltype(&::x) x;
    CUDA_SYM(INIT_SYM)
    #undef INIT_SYM
};

void initializeNVVMState(terra_State * T) {
    if (!T->cuda->initialized) {
        //dynamically assign all of our symbols
        #define INIT_SYM(x) \
            T->cuda->x = (decltype(&x)) llvm::sys::DynamicLibrary::SearchForAddressOfSymbol(#x); \
            assert(T->cuda->x);
            CUDA_SYM(INIT_SYM)
        #undef INIT_SYM
        T->cuda->initialized = 1;
    }
}

static void annotateKernel(terra_State * T, llvm::Module * M, llvm::Function * kernel, const char * name, int value) {
    llvm::LLVMContext & ctx = M->getContext();
    std::vector<METADATA_ROOT_TYPE *> vals;
    llvm::NamedMDNode * annot = M->getOrInsertNamedMetadata("nvvm.annotations");
    llvm::MDString * str = llvm::MDString::get(ctx, name);
    #if LLVM_VERSION <= 35
    vals.push_back(kernel);
    vals.push_back(str);
    vals.push_back(llvm::ConstantInt::get(llvm::Type::getInt32Ty(ctx), value));
    #else
    vals.push_back(llvm::ValueAsMetadata::get(kernel));
    vals.push_back(str);
    vals.push_back(llvm::ConstantAsMetadata::get(llvm::ConstantInt::get(llvm::Type::getInt32Ty(ctx), value)));
    #endif
    llvm::MDNode * node = llvm::MDNode::get(ctx, vals);
    annot->addOperand(node);
}

static const char * cudadatalayout = "e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-v16:16:16-v32:32:32-v64:64:64-v128:128:128-n16:32:64";

#if LLVM_VERSION <= 38
class RemoveAttr : public llvm::InstVisitor<RemoveAttr> {
public:
    void visitCallInst(llvm::CallInst & I) {
        I.setAttributes(llvm::AttributeSet());
    }
};
#endif

void moduleToPTX(terra_State * T, llvm::Module * M, int major, int minor, std::string * buf, const char * libdevice) {

#if LLVM_VERSION <= 38
    for(llvm::Module::iterator it = M->begin(), end = M->end(); it != end; ++it) {
        it->setAttributes(llvm::AttributeSet()); //remove annotations because syntax doesn't match
        RemoveAttr A;
        A.visit(&*it); //remove annotations on CallInsts as well.
    }
#endif
    int nmajor,nminor;
    CUDA_DO(T->cuda->nvvmVersion(&nmajor,&nminor));
    int nversion = nmajor*10 + nminor;
    if(nversion >= 12)
        M->setTargetTriple("nvptx64-nvidia-cuda");
    else
        M->setTargetTriple(""); //clear these because nvvm doesn't like them
    M->setDataLayout(""); //nvvm doesn't like data layout either

    std::stringstream device;
    device << "-arch=compute_" << major << minor;
    std::string deviceopt = device.str();

#if LLVM_VERSION < 50
    std::string llvmir;
    {
        llvm::raw_string_ostream output(llvmir);
        #if LLVM_VERSION >= 38
        M->setDataLayout(cudadatalayout);
        llvm::WriteBitcodeToFile(M, output);
        #else
        llvm::formatted_raw_ostream foutput(output);
        foutput << "target datalayout = \"" << cudadatalayout << "\";\n";
        foutput << *M;
        #endif
    }

    nvvmProgram prog;
    CUDA_DO(T->cuda->nvvmCreateProgram(&prog));

    // Add libdevice module first
    if (libdevice != NULL) {
      std::ifstream libdeviceFile(libdevice);
      std::stringstream sstr;
      sstr << libdeviceFile.rdbuf();
      std::string libdeviceStr = sstr.str();
      size_t libdeviceModSize = libdeviceStr.size();
      const char* libdeviceMod = libdeviceStr.data();
      CUDA_DO(T->cuda->nvvmAddModuleToProgram(prog, libdeviceMod, libdeviceModSize, "libdevice"));
    }

    CUDA_DO(T->cuda->nvvmAddModuleToProgram(prog, llvmir.data(), llvmir.size(), M->getModuleIdentifier().c_str()));
    int numOptions = 1;
    const char * options[] = { deviceopt.c_str() };

    size_t size;
    int err = T->cuda->nvvmCompileProgram(prog, numOptions, options);
    if (err != CUDA_SUCCESS) {
        CUDA_DO(T->cuda->nvvmGetProgramLogSize(prog,&size));
        buf->resize(size);
        CUDA_DO(T->cuda->nvvmGetProgramLog(prog, &(*buf)[0]));
        terra_reporterror(T,"%s:%d: nvvm error reported (%d)\n %s\n",__FILE__,__LINE__,err,buf->c_str());

    }
    CUDA_DO(T->cuda->nvvmGetCompiledResultSize(prog, &size));
    buf->resize(size);
    CUDA_DO(T->cuda->nvvmGetCompiledResult(prog, &(*buf)[0]));
#else
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
    auto E_LDEVICE = llvm::parseBitcodeFile(MB->get()->getMemBufferRef(), M->getContext());

    if (auto Err = E_LDEVICE.takeError()) {
        llvm::logAllUnhandledErrors(std::move(Err), llvm::errs(), "[CUDA Error] ");
        return;
    }

    auto &LDEVICE = *E_LDEVICE;


    llvm::TargetOptions opt;
    auto RM = llvm::Optional<llvm::Reloc::Model>();
    auto TargetMachine = Target->createTargetMachine("nvptx64-nvidia-cuda", cpuopt, Features, opt, RM);

    LDEVICE->setTargetTriple("nvptx64-nvidia-cuda");
    LDEVICE->setDataLayout(TargetMachine->createDataLayout());

    llvm::Linker Linker(*M);
    Linker.linkInModule(std::move(LDEVICE));

    M->setDataLayout(TargetMachine->createDataLayout());

    llvm::SmallString<2048> dest;
    llvm::raw_svector_ostream str_dest(dest);

    llvm::PassManagerBuilder PMB;
    PMB.OptLevel = 3;
    PMB.SizeLevel = 0;
    PMB.LoopVectorize = false;
    auto FileType = llvm::TargetMachine::CGFT_AssemblyFile;

    llvm::legacy::PassManager PM;
    TargetMachine->adjustPassManager(PMB);

    PMB.populateModulePassManager(PM);

    if (TargetMachine->addPassesToEmitFile(PM, str_dest, FileType)) {
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

    (*buf) = dest.str();
#endif
}

//cuda doesn't like llvm generic names, so we replace non-identifier symbols here
static std::string sanitizeName(std::string name) {
    std::string s;
    llvm::raw_string_ostream out(s);
    for(size_t i = 0; i < name.size(); i++) {
        char c = name[i];
        if(isalnum(c) || c == '_')
            out << c;
        else
            out << "_$" << (int) c << "_";
    }
    out.flush();
    return s;
}


int terra_toptx(lua_State * L) {
    terra_State * T = terra_getstate(L, 1);
    initializeNVVMState(T);
    lua_getfield(L,1,"llvm_cu");
    TerraCompilationUnit * CU = (TerraCompilationUnit*) terra_tocdatapointer(L,-1);
    llvm::Module * M = CU->M;
    int annotations = 2;
    int dumpmodule = lua_toboolean(L,3);
    int version = lua_tonumber(L,4);
    int major = version / 10;
    int minor = version % 10;
    const char * libdevice = lua_tostring(L,5);

    int N = lua_objlen(L,annotations);
    for(int i = 0; i < N; i++) {
        lua_rawgeti(L,annotations,i+1); // {kernel,annotation,value}
        lua_rawgeti(L,-1,1); //kernel name
        lua_rawgeti(L,-2,2); // annotation name
        lua_rawgeti(L,-3,3); // annotation value
        const char * kernelname = luaL_checkstring(L,-3);
        const char * annotationname = luaL_checkstring(L,-2);
        int annotationvalue = luaL_checkint(L,-1);
        llvm::Function * kernel = M->getFunction(kernelname);
        assert(kernel);
        annotateKernel(T,M,kernel,annotationname,annotationvalue);
        lua_pop(L,4); //annotation table and 3 values in it
    }

    //sanitize names
    for(llvm::Module::iterator it = M->begin(), end = M->end(); it != end; ++it) {
        const char * prefix = "cudart:";
        size_t prefixsize = strlen(prefix);
        std::string name = it->getName();
        if(name.size() >= prefixsize && name.substr(0,prefixsize) == prefix) {
            std::string shortname = name.substr(prefixsize);
            it->setName(shortname);
        } if(!it->isDeclaration()) {
            it->setName(sanitizeName(it->getName()));
        }
    }
    for(llvm::Module::global_iterator it = M->global_begin(), end = M->global_end(); it != end; ++it) {
        it->setName(sanitizeName(it->getName()));
    }

    std::string ptx;
    moduleToPTX(T,M,major,minor,&ptx,libdevice);
    if(dumpmodule) {
        fprintf(stderr,"CUDA Module:\n");
        #if LLVM_VERSION < 38
        M->dump();
        #else
        M->print(llvm::errs(), nullptr);
        #endif
        fprintf(stderr,"Generated PTX:\n%s\n",ptx.c_str());
    }
    lua_pushstring(L,ptx.c_str());
    return 1;
}

int terra_cudainit(struct terra_State * T) {
    lua_getfield(T->L,LUA_GLOBALSINDEX,"terra");
    lua_getfield(T->L,-1,"cudalibpaths");
    lua_getfield(T->L,-1,"nvvm");
    const char * libnvvmpath = lua_tostring(T->L,-1);
    lua_pop(T->L,2); //path and cudalibpaths
    if(llvm::sys::DynamicLibrary::LoadLibraryPermanently(libnvvmpath)) {
        llvm::SmallString<256> err;
        err.append("failed to load libnvvm at: ");
        err.append(libnvvmpath);
        lua_pushstring(T->L,err.c_str());
        lua_setfield(T->L,-2,"cudaloaderror");
        lua_pop(T->L,1); //terralib
        return 0; //couldn't find the libnvvm library, do not load cudalib.lua
    }
    T->cuda = (terra_CUDAState*) malloc(sizeof(terra_CUDAState));
    T->cuda->initialized = 0; /* actual CUDA initalization is done on first call to terra_cudacompile */
                              /* this function just registers all the Lua state associated with CUDA */

    lua_pushlightuserdata(T->L,(void*)T);
    lua_pushcclosure(T->L,terra_toptx,1);
    lua_setfield(T->L,-2,"toptximpl");
    lua_pop(T->L,1); //terralib
    int err = terra_loadandrunbytecodes(T->L, (const unsigned char *)luaJIT_BC_cudalib,luaJIT_BC_cudalib_SIZE, "cudalib.lua");
    if(err) {
        return err;
    }
    return 0;
}

#else
/* cuda disabled, just do nothing */
int terra_cudainit(struct terra_State * T) {
    return 0;
}
#endif

int terra_cudafree(struct terra_State * T) {
    //currently nothing to clean up
    return 0;
}
