#include "tcwrapper.h"
#include "terra.h"
#include <assert.h>
#include <stdio.h>
extern "C" {
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
}

#include "tobj.h"

#include <cstdio>
#include <string>
#include <sstream>

#include "clang/AST/ASTConsumer.h"
#include "clang/AST/RecursiveASTVisitor.h"
#include "clang/Basic/Diagnostic.h"
#include "clang/Basic/FileManager.h"
#include "clang/Basic/SourceManager.h"
#include "clang/Basic/TargetOptions.h"
#include "clang/Basic/TargetInfo.h"
#include "clang/Frontend/CompilerInstance.h"
#include "clang/Lex/Preprocessor.h"
#include "clang/Parse/ParseAST.h"
#include "clang/Rewrite/Rewriter.h"
#include "clang/Rewrite/Rewriters.h"
#include "llvm/Support/Host.h"
#include "llvm/LLVMContext.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Module.h"
#include "clang/CodeGen/CodeGenAction.h"
#include "clang/CodeGen/ModuleBuilder.h"
#include "llvm/ExecutionEngine/ExecutionEngine.h"
#include "llvm/ExecutionEngine/JIT.h"
#include "llvm/Linker.h"

#include "tcompilerstate.h"

using namespace clang;


// part of the setup is adapted from: http://eli.thegreenplace.net/2012/06/08/basic-source-to-source-transformation-with-clang/

// By implementing RecursiveASTVisitor, we can specify which AST nodes
// we're interested in by overriding relevant methods.
class IncludeCVisitor : public RecursiveASTVisitor<IncludeCVisitor>
{
public:
    IncludeCVisitor(Rewriter &R, std::stringstream & o, Obj * res)
        : TheRewriter(R),
          output(o),
          result(res),
          L(res->getState()),
          ref_table(res->getRefTable())
    {}

    void InitType(const char * name, Obj * tt) {
        lua_getfield(L, LUA_GLOBALSINDEX, name);
        tt->initFromStack(L,ref_table);
    }
    bool GetType(QualType T, Obj * tt) {
        T = Context->getCanonicalType(T);
        const Type *Ty = T.getTypePtr();
        
        switch (Ty->getTypeClass()) {
          case Type::Record:
            printf("NYI - structs\n");
            return false; //TODO
          case Type::Builtin:
            switch (cast<BuiltinType>(Ty)->getKind()) {
            case BuiltinType::Void:
              InitType("uint8",tt);
                return true;
            case BuiltinType::Bool:
                assert(!"bool?");
                return false;
            case BuiltinType::Char_S:
            case BuiltinType::Char_U:
            case BuiltinType::SChar:
            case BuiltinType::UChar:
            case BuiltinType::Short:
            case BuiltinType::UShort:
            case BuiltinType::Int:
            case BuiltinType::UInt:
            case BuiltinType::Long:
            case BuiltinType::ULong:
            case BuiltinType::LongLong:
            case BuiltinType::ULongLong:
            case BuiltinType::WChar_S:
            case BuiltinType::WChar_U:
            case BuiltinType::Char16:
            case BuiltinType::Char32: {
                std::stringstream ss;
                if (Ty->isUnsignedIntegerType())
                ss << "u";
                ss << "int";
                int sz = Context->getTypeSize(T);
                ss << sz;
                InitType(ss.str().c_str(),tt);
                return true;
            }
            case BuiltinType::Half:
                return false;
            case BuiltinType::Float:
                InitType("float",tt);
                return true;
            case BuiltinType::Double:
                InitType("double",tt);
                return true;
            case BuiltinType::LongDouble:
            case BuiltinType::NullPtr:
            case BuiltinType::UInt128:
            default:
                return false;
            }
          case Type::Complex:
          case Type::LValueReference:
          case Type::RValueReference:
            return false;
          case Type::Pointer: {
            const PointerType *PTy = cast<PointerType>(Ty);
            QualType ETy = PTy->getPointeeType();
            Obj t2;
            if(!GetType(ETy,&t2)) {
                return false;
            }
            lua_getfield(L, LUA_GLOBALSINDEX, "terra");
            lua_getfield(L, -1, "types");
            lua_getfield(L, -1, "pointer");
            lua_remove(L,-2);
            lua_remove(L,-2);
            t2.push();
            lua_call(L,1,1);
            tt->initFromStack(L, ref_table);
            return true;
          }

          case Type::VariableArray:
          case Type::IncompleteArray:
          case Type::ConstantArray:
          case Type::ExtVector:
          case Type::Vector:
          case Type::FunctionNoProto:
          case Type::FunctionProto:
          case Type::ObjCObject:
          case Type::ObjCInterface:
          case Type::ObjCObjectPointer:
            return false;
          case Type::Enum:
            printf("NYI - enum\n");
            return false;


          case Type::BlockPointer:
          case Type::MemberPointer:
          case Type::Atomic:
          default:
            return false;
        }
    }
    bool VisitFunctionDecl(FunctionDecl *f) {
         // Function name
        DeclarationName DeclName = f->getNameInfo().getName();
        std::string FuncName = DeclName.getAsString();
        //printf("FuncName: %s\n", FuncName.c_str());

        if(f->isVariadic()) {
            printf("NYI - variadic\n");
            return true;
        }
        Obj returns,parameters;
        result->newlist(&returns);
        result->newlist(&parameters);
        
        QualType RT = f->getResultType();
        if(!RT->isVoidType()) {
            Obj typ;
            if(!GetType(RT,&typ)) {
                return true;
            }
            typ.push();
            returns.addentry();
        }
        
        for(size_t i = 0; i < f->getNumParams(); i++) {
            const ParmVarDecl * p = f->getParamDecl(i);
            QualType PT = p->getType();
            //printf("param: %s\n",PT.getCanonicalType().getAsString().c_str());
            Obj typ;
            if(!GetType(PT,&typ)) {
                return true;
            }
            typ.push();
            parameters.addentry();
        }
        
        //make sure this function is live in codegen by creating a dummy reference to it (void) is to suppress unused warnings
        output << "    (void)" << FuncName << ";\n";         
        CreateFunction(FuncName,&parameters,&returns);
        
        return true;
    }
    void CreateFunction(const std::string & name, Obj * parameters, Obj * returns) {
        lua_getfield(L, LUA_GLOBALSINDEX, "terra");
        lua_getfield(L, -1, "newcfunction");
        lua_remove(L,-2); //terra table
        lua_pushstring(L, name.c_str());
        parameters->push();
        returns->push();
        lua_call(L, 3, 1);
        result->setfield(name.c_str());
    }
    void SetContext(ASTContext * ctx) {
        Context = ctx;
    }
private:
    std::stringstream & output;
    Rewriter &TheRewriter;
    Obj * result;
    lua_State * L;
    int ref_table;
    ASTContext * Context;
};

class IncludeCConsumer : public ASTConsumer
{
public:
    IncludeCConsumer(Rewriter &R,std::stringstream & o, Obj * result)
        : Visitor(R,o,result)
    {}

    virtual void Initialize(ASTContext &Context) {
        Visitor.SetContext(&Context);
    }

    virtual bool HandleTopLevelDecl(DeclGroupRef DR) {
        for (DeclGroupRef::iterator b = DR.begin(), e = DR.end();
             b != e; ++b)
            // Traverse the declaration using our AST visitor.
            Visitor.TraverseDecl(*b);
        return true;
    }

private:
    IncludeCVisitor Visitor;
};

static void dorewrite(terra_State * T, const char * filename, std::string * output, Obj * result) {
    	
    // CompilerInstance will hold the instance of the Clang compiler for us,
    // managing the various objects needed to run the compiler.
    CompilerInstance TheCompInst;
    TheCompInst.createDiagnostics(0, 0);
    CompilerInvocation::CreateFromArgs(TheCompInst.getInvocation(), NULL, NULL, TheCompInst.getDiagnostics());
    
    TargetInfo *TI = TargetInfo::CreateTargetInfo(TheCompInst.getDiagnostics(), TheCompInst.getTargetOpts());
    TheCompInst.setTarget(TI);

    TheCompInst.createFileManager();
    FileManager &FileMgr = TheCompInst.getFileManager();
    TheCompInst.createSourceManager(FileMgr);
    SourceManager &SourceMgr = TheCompInst.getSourceManager();
    TheCompInst.createPreprocessor();
    TheCompInst.createASTContext();

    // A Rewriter helps us manage the code rewriting task.
    Rewriter TheRewriter;
    TheRewriter.setSourceMgr(SourceMgr, TheCompInst.getLangOpts());

    // Set the main file handled by the source manager to the input file.
    const FileEntry *FileIn = FileMgr.getFile(filename);
    SourceMgr.createMainFileID(FileIn);
    TheCompInst.getDiagnosticClient().BeginSourceFile(TheCompInst.getLangOpts(),&TheCompInst.getPreprocessor());

    // Create an AST consumer instance which is going to get called by
    // ParseAST.
  
    std::stringstream dummy;
    IncludeCConsumer TheConsumer(TheRewriter,dummy,result);

    // Parse the file to AST, registering our consumer as the AST consumer.
    ParseAST(TheCompInst.getPreprocessor(), &TheConsumer,
             TheCompInst.getASTContext());

    // At this point the rewriter's buffer should be full with the rewritten
    // file contents.
    const RewriteBuffer *RewriteBuf =
        TheRewriter.getRewriteBufferFor(SourceMgr.getMainFileID());
    
    llvm::MemoryBuffer * mb = FileMgr.getBufferForFile(FileIn);
    std::ostringstream out;
    out << std::string(mb->getBufferStart(),mb->getBufferEnd()) << "\n" 
    << "void __makeeverythinginclanglive_" << T->C->next_unused_id++ << "() {\n"
    << dummy.str() << "\n}\n";
    *output = out.str();
    //printf("output is %s\n",(*output).c_str());
}

static int dofile(terra_State * T, const char * filename, Obj * result) {
	
    std::string buffer;
    dorewrite(T,filename,&buffer,result);
    
    // CompilerInstance will hold the instance of the Clang compiler for us,
    // managing the various objects needed to run the compiler.
    CompilerInstance TheCompInst;
    TheCompInst.createDiagnostics(0, 0);
    CompilerInvocation::CreateFromArgs(TheCompInst.getInvocation(), NULL, NULL, TheCompInst.getDiagnostics());
    
    TargetInfo *TI = TargetInfo::CreateTargetInfo(TheCompInst.getDiagnostics(), TheCompInst.getTargetOpts());
    TheCompInst.setTarget(TI);

    TheCompInst.createFileManager();
    FileManager &FileMgr = TheCompInst.getFileManager();
    TheCompInst.createSourceManager(FileMgr);
    SourceManager &SourceMgr = TheCompInst.getSourceManager();
    TheCompInst.createPreprocessor();
    TheCompInst.createASTContext();

    // A Rewriter helps us manage the code rewriting task.
    Rewriter TheRewriter;
    TheRewriter.setSourceMgr(SourceMgr, TheCompInst.getLangOpts());

    // Set the main file handled by the source manager to the input file.
    const FileEntry *FileIn = FileMgr.getFile(filename);
    llvm::MemoryBuffer * membuffer = llvm::MemoryBuffer::getMemBufferCopy(buffer, filename);
    SourceMgr.createMainFileIDForMemBuffer(membuffer);
    TheCompInst.getDiagnosticClient().BeginSourceFile(TheCompInst.getLangOpts(),&TheCompInst.getPreprocessor());

    CodeGenOptions CGO;
    CodeGenerator * codegen = CreateLLVMCodeGen(TheCompInst.getDiagnostics(), "mymodule", CGO, llvm::getGlobalContext() );

	ParseAST(TheCompInst.getPreprocessor(),
			codegen,
			TheCompInst.getASTContext());

    llvm::Module * mod = codegen->ReleaseModule();
    
    if(mod) {
        std::string err;
        if(llvm::Linker::LinkModules(T->C->m, mod, 0, &err)) {
            terra_reporterror(T,"llvm: %s\n",err.c_str());
        }
        //mod->dump();
    } else {
        terra_reporterror(T,"compilation of included c code failed\n");
    }
    
    delete codegen;
    
    return 0;
}

int include_c(lua_State * L) {
    terra_State * T = (terra_State*) lua_topointer(L,lua_upvalueindex(1));
    assert(T->L == L);
    const char * fname = luaL_checkstring(L, -1);
    //printf("loading %s\n",fname);
    
    lua_newtable(L); //return a table of loaded functions
    int ref_table = lobj_newreftable(L);
    {
        Obj result;
        lua_pushvalue(L, -2);
        result.initFromStack(L, ref_table);
        dofile(T,fname,&result);
        //result.dump();
    }
    
    lobj_removereftable(L, ref_table);
    return 1;
}

int register_c_function(lua_State * L) {
    terra_State * T = (terra_State*) lua_topointer(L,lua_upvalueindex(1));
    assert(T->L == L);
    
    int ref_table = lobj_newreftable(L);
    {
        Obj fn;
        lua_pushvalue(L, -2);
        fn.initFromStack(L,ref_table);
        const char * name = fn.string("name");
        llvm::Function * llvmfn = T->C->m->getFunction(name);
        assert(llvmfn);
        lua_pushlightuserdata(L, llvmfn);
        fn.setfield("llvm_function");
        void * fptr = T->C->ee->getPointerToFunction(llvmfn);
        assert(fptr);
        void ** data = (void**) lua_newuserdata(L,sizeof(void*));
        *data = fptr;
        fn.setfield("fptr");
    }
    lobj_removereftable(L, ref_table);
    
    
    return 0;
}

void terra_cwrapperinit(terra_State * T) {
    lua_getfield(T->L,LUA_GLOBALSINDEX,"terra");
    
    lua_pushlightuserdata(T->L,(void*)T);
    lua_pushcclosure(T->L,include_c,1);
    lua_setfield(T->L,-2,"registercfile");
    
    lua_pushlightuserdata(T->L,(void*)T);
    lua_pushcclosure(T->L,register_c_function,1);
    lua_setfield(T->L,-2,"registercfunction");
    
    lua_pop(T->L,-1); //terra object
}