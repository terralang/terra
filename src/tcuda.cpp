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
#include "cudalib.h"
#include <sstream>
#ifndef _WIN32
#include <unistd.h>
#endif

struct terra_CUDAState {
    int initialized;
    CUdevice D;
    CUcontext C;
};

#define CUDA_DO(err) do { \
    int e = err; \
    if(e != CUDA_SUCCESS) { \
        terra_reporterror(T,"%s:%d: %s cuda reported error %d",__FILE__,__LINE__,#err,e); \
    } \
} while(0)

CUresult initializeCUDAState(terra_State * T) {
    if (!T->cuda->initialized) {
        T->cuda->initialized = 1;
        CUDA_DO(cuInit(0));
        CUDA_DO(cuCtxGetCurrent(&T->cuda->C));
        if(T->cuda->C) {
            //there is already a valid cuda context, so use that
            CUDA_DO(cuCtxGetDevice(&T->cuda->D));
            return CUDA_SUCCESS;
        }
        CUDA_DO(cuDeviceGet(&T->cuda->D,0));
        CUDA_DO(cuCtxCreate(&T->cuda->C, 0, T->cuda->D));
    }
    return CUDA_SUCCESS;
}
static void annotateKernel(terra_State * T, llvm::Module * M, llvm::Function * kernel, const char * name, int value) {
    std::vector<llvm::Value *> vals;
    llvm::NamedMDNode * annot = M->getOrInsertNamedMetadata("nvvm.annotations");
    llvm::MDString * str = llvm::MDString::get(*T->C->ctx, name);
    vals.push_back(kernel);
    vals.push_back(str);
    vals.push_back(llvm::ConstantInt::get(llvm::Type::getInt32Ty(*T->C->ctx), value));  
    llvm::MDNode * node = llvm::MDNode::get(*T->C->ctx, vals);
    annot->addOperand(node); 
}

static const char * cudadatalayout = "e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-v16:16:16-v32:32:32-v64:64:64-v128:128:128-n16:32:64";
class RemoveAttr : public llvm::InstVisitor<RemoveAttr> {
public:
    void visitCallInst(llvm::CallInst & I) {
        I.setAttributes(llvm::AttributeSet());
    }
};

CUresult moduleToPTX(terra_State * T, llvm::Module * M, std::string * buf) {
    for(llvm::Module::iterator it = M->begin(), end = M->end(); it != end; ++it) {
        it->setAttributes(llvm::AttributeSet()); //remove annotations because syntax doesn't match
        RemoveAttr A;
        A.visit(it); //remove annotations on CallInsts as well.
    }
    
    M->setTargetTriple(""); //clear these because nvvm doesn't like them
    M->setDataLayout("");
    
    int major,minor;
    CUDA_DO(cuDeviceComputeCapability(&major,&minor,T->cuda->D));
    std::stringstream device;
    device << "-arch=compute_" << major << minor;
    std::string deviceopt = device.str();
    
    std::string llvmir;
    {
        llvm::raw_string_ostream output(llvmir);
        llvm::formatted_raw_ostream foutput(output);
        foutput << "target datalayout = \"" << cudadatalayout << "\";\n";
        foutput << *M;
    }
    nvvmProgram prog;
    CUDA_DO(nvvmCreateProgram(&prog));
    CUDA_DO(nvvmAddModuleToProgram(prog, llvmir.data(), llvmir.size(), M->getModuleIdentifier().c_str()));
    int numOptions = 1;
    const char * options[] = { deviceopt.c_str() };
    
    size_t size;
    int err = nvvmCompileProgram(prog, numOptions, options);
    if (err != CUDA_SUCCESS) {
        CUDA_DO(nvvmGetProgramLogSize(prog,&size));
        buf->resize(size);
        CUDA_DO(nvvmGetProgramLog(prog, &(*buf)[0]));
        terra_reporterror(T,"%s:%d: nvvm error reported (%d)\n %s\n",__FILE__,__LINE__,err,buf->c_str());
        
    }
    CUDA_DO(nvvmGetCompiledResultSize(prog, &size));
    buf->resize(size);
    CUDA_DO(nvvmGetCompiledResult(prog, &(*buf)[0]));
    return CUDA_SUCCESS;
}

//cuda doesn't like llvm generic names, so we replace non-identifier symbols here
static std::string sanitizeName(std::string name) {
    std::string s;
    llvm::raw_string_ostream out(s);
    for(int i = 0; i < name.size(); i++) {
        char c = name[i];
        if(isalnum(c) || c == '_')
            out << c;
        else
            out << "_$" << (int) c << "_";
    }
	out.flush();
    return s;
}


int terra_cudacompile(lua_State * L) {
    terra_State * T = terra_getstate(L, 1);
    initializeCUDAState(T);
    int tbl = 1,annotations = 2;
    int dumpmodule = lua_toboolean(L,3);
    
    std::vector<std::string> globalnames;
    std::vector<llvm::GlobalValue *> globals;
    
    lua_pushnil(L);
    while (lua_next(L, tbl) != 0) {
        const char * key = luaL_checkstring(L,-2);
        lua_getfield(L,-1,"llvm_value");
        llvm::GlobalValue * v = (llvm::GlobalValue*) lua_topointer(L,-1);
        if(dumpmodule) {
            fprintf(stderr,"Add Global Value:\n");
            v->dump();
        }
        assert(v);
        globalnames.push_back(key);
        globals.push_back(v);
        lua_pop(L,2);  /* variant, value pointer */
    }
    
    llvm::Module * M = llvmutil_extractmodule(T->C->m, T->C->tm, &globals,&globalnames, false);

    int N = lua_objlen(L,annotations);
    for(size_t i = 0; i < N; i++) {
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
        if(it->getName().startswith(prefix))
            it->setName(it->getName().substr(strlen(prefix)));
        if(!it->isDeclaration())
            it->setName(sanitizeName(it->getName()));
    }
    for(llvm::Module::global_iterator it = M->global_begin(), end = M->global_end(); it != end; ++it) {
        it->setName(sanitizeName(it->getName()));
    }
	
    std::string ptx;
    CUDA_DO(moduleToPTX(T,M,&ptx));
    if(dumpmodule) {
        fprintf(stderr,"CUDA Module:\n");
        M->dump();
        fprintf(stderr,"Generated PTX:\n%s\n",ptx.c_str());
    }
    delete M;
    CUmodule cudaM;
    
    CUlinkState linkState;
    char error_log[8192];
    
    CUjit_option options[] = {CU_JIT_ERROR_LOG_BUFFER,CU_JIT_ERROR_LOG_BUFFER_SIZE_BYTES};
    void * option_values[] = { error_log, (void*)8192 };
    void * cubin;
    size_t cubinSize;
    CUDA_DO(cuLinkCreate(2,options,option_values,&linkState));
    
    CUresult err = cuLinkAddData(linkState,CU_JIT_INPUT_PTX,(void*)ptx.c_str(),ptx.length()+1,0,0,0,0);
    if(err != CUDA_SUCCESS) {
        terra_reporterror(T,"%s:%d: %s",__FILE__,__LINE__,error_log);
    }
    CUDA_DO(cuLinkAddFile(linkState,CU_JIT_INPUT_LIBRARY,TERRA_CUDADEVRT, 0, NULL, NULL));
    CUDA_DO(cuLinkComplete(linkState,&cubin,&cubinSize));
    
#ifndef _WIN32
    if(dumpmodule) {
        llvm::SmallString<256> tmpname;
        llvmutil_createtemporaryfile("cudamodule", "cubin", tmpname);
        FILE * f = fopen(tmpname.c_str(),"w");
        fwrite(cubin,cubinSize,1,f);
        fclose(f);
        const char * args[] = { TERRA_CUDANVDISASM, "--print-life-ranges", tmpname.c_str(), NULL };
        llvmutil_executeandwait(LLVM_PATH_TYPE(TERRA_CUDANVDISASM), args, NULL);
        unlink(tmpname.c_str());
    }
#endif

    CUDA_DO(cuModuleLoadData(&cudaM, cubin));
    CUDA_DO(cuLinkDestroy(linkState));

    lua_getfield(L,LUA_GLOBALSINDEX,"terra");
    lua_getfield(L,-1,"cudamakekernelwrapper");
    int mkwrapper = lua_gettop(L);

    lua_newtable(L);
    int resulttbl = lua_gettop(L);

    lua_pushnil(L);
    for(size_t i = 0; lua_next(L,tbl) != 0; i++) {
        const char * key = luaL_checkstring(L,-2);
        lua_getfield(L,-1,"llvm_value");
        llvm::GlobalValue * v = (llvm::GlobalValue*) lua_topointer(L,-1);
        lua_pop(L,1);
        if(llvm::dyn_cast<llvm::Function>(v)) {
            CUfunction func;
            CUDA_DO(cuModuleGetFunction(&func, cudaM, sanitizeName(key).c_str()));
            //HACK: we need to get this value, as a constant, to the makewrapper function
            //currently the only constants that Terra supports programmatically are string constants
            //eventually we will change this to make a Terra constant of type CUfunction when we have
            //the appropriate API
            lua_pushlstring(L,(char*)&func,sizeof(CUfunction));
            lua_pushvalue(L,mkwrapper);
            lua_insert(L,-3); /*stack is now <mkwrapper> <variant (value from table)> <string of CUfunction> <mkwrapper> (TOP) */
            lua_call(L,2,1);
        } else {
            assert(llvm::dyn_cast<llvm::GlobalVariable>(v));
            CUdeviceptr dptr;
            size_t bytes;
            CUDA_DO(cuModuleGetGlobal(&dptr,&bytes,cudaM,sanitizeName(key).c_str()));
            lua_pop(L,1); //remove value
            lua_pushlightuserdata(L,(void*)dptr);
        }

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
