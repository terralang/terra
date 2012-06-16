#include "tcwrapper.h"
#include "terra.h"
#include <assert.h>
#include <stdio.h>
extern "C" {
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
}


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

using namespace clang;

// By implementing RecursiveASTVisitor, we can specify which AST nodes
// we're interested in by overriding relevant methods.
class MyASTVisitor : public RecursiveASTVisitor<MyASTVisitor>
{
public:
    MyASTVisitor(Rewriter &R, std::stringstream & o)
        : TheRewriter(R),
          output(o)
    {}

    bool VisitFunctionDecl(FunctionDecl *f) {
        // Only function definitions (with bodies), not declarations.
        //if (f->hasBody()) {
            //Stmt *FuncBody = f->getBody();

            // Type name as string
            
            QualType QT = f->getResultType();
            std::string TypeStr = QT.getAsString();

            // Function name
            DeclarationName DeclName = f->getNameInfo().getName();
            std::string FuncName = DeclName.getAsString();

            printf("FUNCNAME: %s\n",FuncName.c_str());
            
            // Add comment before
            output << "void myfn_" << FuncName << "() {}\n";
            
        //}

        return true;
    }

private:
    void AddBraces(Stmt *s);
    std::stringstream & output;
    Rewriter &TheRewriter;
};

// Implementation of the ASTConsumer interface for reading an AST produced
// by the Clang parser.
class MyASTConsumer : public ASTConsumer
{
public:
    MyASTConsumer(Rewriter &R,std::stringstream & o)
        : Visitor(R,o)
    {}

    virtual void Initialize(ASTContext &Context) {
        printf("INIT\n");
    }

    virtual bool HandleTopLevelDecl(DeclGroupRef DR) {
        for (DeclGroupRef::iterator b = DR.begin(), e = DR.end();
             b != e; ++b)
            // Traverse the declaration using our AST visitor.
            Visitor.TraverseDecl(*b);
        return true;
    }

private:
    MyASTVisitor Visitor;
};

static void dorewrite(const char * filename, std::string * output) {
    	
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
    MyASTConsumer TheConsumer(TheRewriter,dummy);

    // Parse the file to AST, registering our consumer as the AST consumer.
    ParseAST(TheCompInst.getPreprocessor(), &TheConsumer,
             TheCompInst.getASTContext());

    // At this point the rewriter's buffer should be full with the rewritten
    // file contents.
    const RewriteBuffer *RewriteBuf =
        TheRewriter.getRewriteBufferFor(SourceMgr.getMainFileID());
    
    llvm::MemoryBuffer * mb = FileMgr.getBufferForFile(FileIn);
    std::ostringstream out;
    out << std::string(mb->getBufferStart(),mb->getBufferEnd()) << "\n" << dummy.str() << "\n";
    *output = out.str();
    printf("output is %s\n",(*output).c_str());
}

static int dofile(terra_State * T, const char * filename) {
	
    std::string buffer;
    dorewrite(filename,&buffer);
    
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
    if(mod)
        mod->dump();
    
    delete codegen;
    
    return 0;
}

int include_c(lua_State * L) {
    terra_State * T = (terra_State*) lua_topointer(L,lua_upvalueindex(1));
    assert(T->L == L);
    const char * fname = luaL_checkstring(L, -1);
    printf("loading %s\n",fname);
    
    dofile(T,fname);
    //TODO: use clang to populate table of external functions
    //each functions needs to be populated with
    //pointer to the llvm Function object
    //pointer to the clang declaration to disambiguate the types of the function
    
    //each global variable needs to be populated with
    //type
    //tree -- AST of kind "entry" that has a value reference pointing to the GlobalVar
    //Do we need to have initializers for global vars?
    
    //for each typedef we need to create the equivalent type in this table
    
    lua_newtable(L); //return a table of loaded functions
    return 1;
}

void terra_cwrapperinit(terra_State * T) {
    lua_getfield(T->L,LUA_GLOBALSINDEX,"terra");
    lua_pushlightuserdata(T->L,(void*)T);
    lua_pushcclosure(T->L,include_c,1);
    lua_setfield(T->L,-2,"registercfile");
    lua_pop(T->L,-1); //terra object
}