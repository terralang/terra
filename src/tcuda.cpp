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
#include "llvmheaders.h"
#include "terrastate.h"
#include "tcompilerstate.h"
#include "tllvmutil.h"
#include "cudalib.h"

struct terra_CUDAState {
    int initialized;
    CUdevice D;
    CUcontext C;
};

#define CUDA_DO(err) do { \
    CUresult e = err; \
    if(e != CUDA_SUCCESS) { \
        terra_pusherror(T,"%s:%d: %s cuda reported error %d",__FILE__,__LINE__,#err,e); \
        return e; \
    } \
} while(0)

CUresult initializeCUDAState(terra_State * T) {
    if (!T->cuda->initialized) {
        T->cuda->initialized = 1;
        CUDA_DO(cuInit(0));
        CUDA_DO(cuDeviceGet(&T->cuda->D,0));
        CUDA_DO(cuCtxCreate(&T->cuda->C, 0, T->cuda->D));
    }
    return CUDA_SUCCESS;
}
static void markKernel(terra_State * T, llvm::Module * M, llvm::Function * kernel) {
    std::vector<llvm::Value *> vals;
    llvm::NamedMDNode * annot = M->getOrInsertNamedMetadata("nvvm.annotations");
    llvm::MDString * str = llvm::MDString::get(*T->C->ctx, "kernel");
    vals.push_back(kernel);
    vals.push_back(str);
    vals.push_back(llvm::ConstantInt::get(llvm::Type::getInt32Ty(*T->C->ctx), 1));  
    llvm::MDNode * node = llvm::MDNode::get(*T->C->ctx, vals);
    annot->addOperand(node); 
}


CUresult moduleToPTX(terra_State * T, llvm::Module * M, std::string * buf) {
    llvm::raw_string_ostream output(*buf);
    llvm::formatted_raw_ostream foutput(output);
    
    LLVMInitializeNVPTXTargetInfo();
    LLVMInitializeNVPTXTarget();
    LLVMInitializeNVPTXAsmPrinter();
    
    std::string err;
    const llvm::Target *TheTarget = llvm::TargetRegistry::lookupTarget("nvptx64", err);
    
    
    llvm::TargetMachine * TM = 
        TheTarget->createTargetMachine("nvptx64", "sm_20",
                                       "", llvm::TargetOptions(),
                                       llvm::Reloc::Default,llvm::CodeModel::Default,
                                       llvm::CodeGenOpt::Aggressive);
    
    llvm::PassManager PM;
    PM.add(new llvm::TARGETDATA()(*TM->TARGETDATA(get)()));
    if(TM->addPassesToEmitFile(PM, foutput, llvm::TargetMachine::CGFT_AssemblyFile)) {
       printf("addPassesToEmitFile failed\n");
       return CUDA_ERROR_UNKNOWN;
    }
    
    PM.run(*M);
    return CUDA_SUCCESS;
}

int terra_cudacompile(lua_State * L) {
    terra_State * T = terra_getstate(L, 1);
    initializeCUDAState(T);

    int tbl = lua_gettop(L);
    
    std::vector<llvm::Function *> fns;
    
    lua_pushnil(L);
    while (lua_next(L, tbl) != 0) {
        lua_getfield(L,-1,"llvm_function");
        llvm::Function * fn = (llvm::Function*) lua_topointer(L,-1);
        assert(fn);
        fns.push_back(fn);
        lua_pop(L,2);  /* variant, function pointer */
    }
    
    llvm::Module * M = llvmutil_extractmodule(T->C->m, T->C->tm, &fns,NULL);
    M->setDataLayout("e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-v16:16:16-v32:32:32-v64:64:64-v128:128:128-n16:32:64");
    
    for(size_t i = 0; i < fns.size(); i++) {
        llvm::Function * kernel = M->getFunction(fns[i]->getName());
        markKernel(T,M,kernel);
    }
    
    std::string ptx;
    CUDA_DO(moduleToPTX(T,M,&ptx));
    delete M;
    CUmodule cudaM;
    CUDA_DO(cuModuleLoadDataEx(&cudaM, ptx.c_str(), 0, 0, 0));

    lua_getfield(L,LUA_GLOBALSINDEX,"terra");
    lua_getfield(L,-1,"cudamakekernelwrapper");
    int mkwrapper = lua_gettop(L);

    lua_newtable(L);
    int resulttbl = lua_gettop(L);

    lua_pushnil(L);
    for(size_t i = 0; lua_next(L,tbl) != 0; i++) {
        const char * key = luaL_checkstring(L,-2);
        CUfunction func;
        CUDA_DO(cuModuleGetFunction(&func, cudaM, fns[i]->getName().str().c_str()));
        //HACK: we need to get this value, as a constant, to the makewrapper function
        //currently the only constants that Terra supports programmatically are string constants
        //eventually we will change this to make a Terra constant of type CUfunction when we have
        //the appropriate API
        lua_pushlstring(L,(char*)&func,sizeof(CUfunction));
        lua_pushvalue(L,mkwrapper);
        lua_insert(L,-3); /*stack is now <mkwrapper> <variant (value from table)> <string of CUfunction> <mkwrapper> (TOP) */
        lua_call(L,2,1);

        lua_setfield(L,resulttbl,key);
        /* stack is now the key */
    }

    /* stack is now the table holding the terra functions */

    return 1;
}

int terra_cudainit(struct terra_State * T) {
    T->cuda = (terra_CUDAState*) malloc(sizeof(terra_CUDAState));
    T->cuda->initialized = 0; /* actual CUDA initalization is done on first call to terra_cudacompile */
                              /* CUDA init is very expensive, so we only want to do it if the program actually uses cuda*/
                              /* this function just registers all the Lua state associated with CUDA */
    lua_getfield(T->L,LUA_GLOBALSINDEX,"terra");
    lua_pushlightuserdata(T->L,(void*)T);
    lua_pushcclosure(T->L,terra_cudacompile,1);
    lua_setfield(T->L,-2,"cudacompileimpl");

    int err = terra_loadandrunbytecodes(T->L, luaJIT_BC_cudalib,luaJIT_BC_cudalib_SIZE, "cudalib.lua");
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
    //TODO: clean up after cuda
    return 0;
}
