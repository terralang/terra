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

#include "llvmheaders.h"
#include "tcompilerstate.h"
#include "clangpaths.h"

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
          ref_table(res->getRefTable()) {
        
        //create a table to hold the error messages for this import
        lua_newtable(L);
        error_table.initFromStack(L,ref_table);
        
        
        
    }

    void SetMetatable() {
        result->push(); //to set metatable later
        
        //set the metatable for result to fire includetableindex when a thing wasn't found
        lua_newtable(L); //metatable
        lua_getfield(L, LUA_GLOBALSINDEX, "terra");
        lua_getfield(L, -1, "includetableindex");
        lua_remove(L,-2);
        lua_setfield(L, -2, "__index");
        error_table.push();
        lua_setfield(L,-2,"errors");
        
        
        lua_setmetatable(L, -2);
        
        lua_pop(L,1); //remove result table
    }
    
    void InitType(const char * name, Obj * tt) {
        lua_getfield(L, LUA_GLOBALSINDEX, name);
        tt->initFromStack(L,ref_table);
    }
    
    void PushTypeFunction(const char * name) {
        lua_getfield(L, LUA_GLOBALSINDEX, "terra");
        lua_getfield(L, -1, "types");
        lua_getfield(L, -1, name);
        lua_remove(L,-2);
        lua_remove(L,-2);
    }
    
    bool ImportError(const std::string & msg) {
        error_message = msg;
        return false;
    }
    bool GetType(QualType T, Obj * tt) {
        
        T = Context->getCanonicalType(T);
        const Type *Ty = T.getTypePtr();
        
        switch (Ty->getTypeClass()) {
          case Type::Record: {
            const RecordType *RT = dyn_cast<RecordType>(Ty);
            RecordDecl * rd = RT->getDecl();
            if(rd->isStruct()) {
                std::string name = rd->getName();
                //TODO: why do some types not have names?
                if(name == "")
                    name = "anon";
                if(!result->obj(name.c_str(),tt)) {
                    //create new blank struct, fill in with members
                    PushTypeFunction("newstruct");
                    lua_pushstring(L, name.c_str());
                    lua_call(L,1,1);
                    tt->initFromStack(L,ref_table);
                    tt->push();
                    result->setfield(name.c_str()); //register the type (this prevents an infinite loop for recursive types)
                    Obj addentry;
                    tt->obj("addentry",&addentry);
                    
                    
                    //check the fields of this struct, if any one of them is not understandable, then this struct becomes 'opaque'
                    //that is, we insert the type, and link it to its llvm type, so it can be used in terra code
                    //but none of its fields are exposed (since we don't understand the layout)
                    bool opaque = false;
                    size_t ncalls = 0;
                    int stktop = lua_gettop(L);
                    for(RecordDecl::field_iterator it = rd->field_begin(), end = rd->field_end(); it != end; ++it) {
                        if(it->isBitField() || it->isAnonymousStructOrUnion() || !it->getDeclName()) {
                            opaque = true;
                            continue;
                        }
                        DeclarationName declname = it->getDeclName();
                        std::string declstr = declname.getAsString();
                        QualType FT = it->getType();
                        Obj fobj;
                        if(!GetType(FT,&fobj)) {
                            opaque = true;
                            continue;
                        }
                        //arguments to function call add entry are  push onto the lua stack, but the function itself is not called 
                        //it is delayed until we know that all fields are valid
                        lua_checkstack(L, 2);
                        
                        lua_pushstring(L,declstr.c_str());
                        fobj.push();
                        ncalls++;
                    }
                    if(!opaque) {
                        lua_checkstack(L,4);
                        assert(lua_gettop(L) == stktop + 2*ncalls);
                        int first_arg = stktop + 1;
                        for(size_t i = 0; i < ncalls; i++) {
                            addentry.push();
                            tt->push();
                            lua_pushvalue(L, first_arg + 2*i);
                            lua_pushvalue(L, first_arg + 2*i + 1);
                            lua_call(L,3,0); //make the calls addentry to form the struct
                        }
                        assert(lua_gettop(L) == stktop + 2*ncalls);
                    }
                    lua_settop(L,stktop); //reset the stack to before processing fields
                    
                    std::stringstream ss;
                    ss << "struct." << name.c_str();
                    lua_pushstring(L,ss.str().c_str());
                    tt->setfield("llvm_name");
                }
                return true;
            } else {
                return ImportError("non-struct record types are not supported");
            }
          }  break; //TODO
          case Type::Builtin:
            switch (cast<BuiltinType>(Ty)->getKind()) {
            case BuiltinType::Void:
              InitType("uint8",tt);
                return true;
            case BuiltinType::Bool:
                assert(!"bool?");
                break;
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
                break;
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
                break;
            }
          case Type::Complex:
          case Type::LValueReference:
          case Type::RValueReference:
            break;
          case Type::Pointer: {
            const PointerType *PTy = cast<PointerType>(Ty);
            QualType ETy = PTy->getPointeeType();
            Obj t2;
            if(!GetType(ETy,&t2)) {
                return false;
            }
            PushTypeFunction("pointer");
            t2.push();
            lua_call(L,1,1);
            tt->initFromStack(L, ref_table);
            return true;
          }
          
          case Type::VariableArray:
          case Type::IncompleteArray:
            break;
          case Type::ConstantArray: {
            Obj at;
            const ConstantArrayType *ATy = cast<ConstantArrayType>(Ty);
            int sz = ATy->getSize().getZExtValue();
            if(GetType(ATy->getElementType(),&at)) {
                PushTypeFunction("array");
                at.push();
                lua_pushinteger(L, sz);
                lua_call(L,2,1);
                tt->initFromStack(L,ref_table);
                return true;
            } else {
                return false;
            }
          } break;
          case Type::ExtVector:
          case Type::Vector: {
                //printf("making a vector!\n");
                const VectorType *VT = cast<VectorType>(T);
                Obj at;
                if(GetType(VT->getElementType(),&at)) {
                    int n = VT->getNumElements();
                    PushTypeFunction("vector");
                    at.push();
                    lua_pushinteger(L,n);
                    lua_call(L,2,1);
                    tt->initFromStack(L, ref_table);
                    return true;
                } else {
                    return false;
                }
          } break;
          case Type::FunctionNoProto:
                break;
          case Type::FunctionProto: {
                const FunctionProtoType *FT = cast<FunctionProtoType>(Ty);
                //call functype... getNumArgs();
                if(FT && GetFuncType(FT,tt))
                    return true;
                else
                    return false;
                break;
          }
          case Type::ObjCObject:
          case Type::ObjCInterface:
          case Type::ObjCObjectPointer:
          case Type::Enum:
            InitType("uint32",tt);
            return true;
          case Type::BlockPointer:
          case Type::MemberPointer:
          case Type::Atomic:
          default:
            break;
        }
        std::stringstream ss;
        ss << "type not understood: " << T.getAsString().c_str() << " " << Ty->getTypeClass();
        return ImportError(ss.str().c_str());
    }
    void SetErrorReport(const char * field) {
        lua_pushstring(L,error_message.c_str());
        error_table.setfield(field);
    }
    bool VisitTypedefDecl(TypedefDecl * TD) {
        if(TD == TD->getCanonicalDecl() && TD->getDeclContext()->getDeclKind() == Decl::TranslationUnit) {
            llvm::StringRef name = TD->getName();
            QualType QT = Context->getCanonicalType(TD->getUnderlyingType());
            Obj typ;
            if(GetType(QT,&typ)) {
                typ.push();
                result->setfield(name.str().c_str());
                //make sure it stays live
                output << "(void)(" << name.str() << "*) (void*) 0;\n";
            } else {
                SetErrorReport(name.str().c_str());
            }
        }
        return true;
    }
    
    bool GetFuncType(const FunctionProtoType * f, Obj * typ) {
        Obj returns,parameters;
        result->newlist(&returns);
        result->newlist(&parameters);
        
        bool valid = true; //decisions about whether this function can be exported or not are delayed until we have seen all the potential problems
        QualType RT = f->getResultType();
        if(!RT->isVoidType()) {
            Obj rt;
            if(!GetType(RT,&rt)) {
                valid = false;
            } else {
                rt.push();
                returns.addentry();
            }
        }
        for(size_t i = 0; i < f->getNumArgs(); i++) {
            QualType PT = f->getArgType(i);
            Obj pt;
            if(!GetType(PT,&pt)) {
                valid = false; //keep going with attempting to parse type to make sure we see all the reasons why we cannot support this function
            } else if(valid) {
                pt.push();
                parameters.addentry();
            }
        }
        
        if(valid) {
            PushTypeFunction("functype");
            parameters.push();
            returns.push();
            lua_pushboolean(L, f->isVariadic());
            lua_call(L, 3, 1);
            typ->initFromStack(L,ref_table);
        }
        
        return valid;
    }
    bool VisitFunctionDecl(FunctionDecl *f) {
         // Function name
        DeclarationName DeclName = f->getNameInfo().getName();
        std::string FuncName = DeclName.getAsString();
        
        const FunctionProtoType * fntyp = f->getType()->getAs<FunctionProtoType>();
        
        if(!fntyp)
            return true;
        
        Obj typ;
        if(!GetFuncType(fntyp,&typ)) {
            SetErrorReport(FuncName.c_str());
            return true;
        }
        //make sure this function is live in codegen by creating a dummy reference to it (void) is to suppress unused warnings
        output << "    (void)" << FuncName << ";\n";         
        CreateFunction(FuncName,&typ);
        
        return true;
    }
    void CreateFunction(const std::string & name, Obj * typ) {
        lua_getfield(L, LUA_GLOBALSINDEX, "terra");
        lua_getfield(L, -1, "newcfunction");
        lua_remove(L,-2); //terra table
        lua_pushstring(L, name.c_str());
        typ->push();
        lua_call(L, 2, 1);
        result->setfield(name.c_str());
    }
    void SetContext(ASTContext * ctx) {
        Context = ctx;
    }
    ~IncludeCVisitor() { SetMetatable(); } //setting the metatable must be done after type resolution, or attempts to find if types have been initialized will cause name not found errors
private:
    std::stringstream & output;
    Rewriter &TheRewriter;
    Obj * result;
    lua_State * L;
    int ref_table;
    ASTContext * Context;
    Obj error_table;
    std::string error_message;
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

static void dorewrite(terra_State * T, const char * code, const char ** argbegin, const char ** argend, std::string * output, Obj * result) {
    // CompilerInstance will hold the instance of the Clang compiler for us,
    // managing the various objects needed to run the compiler.
    CompilerInstance TheCompInst;
    TheCompInst.createDiagnostics(0, 0);
    
    CompilerInvocation::CreateFromArgs(TheCompInst.getInvocation(), argbegin, argend, TheCompInst.getDiagnostics());
    
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
    llvm::MemoryBuffer * membuffer = llvm::MemoryBuffer::getMemBufferCopy(code, "<buffer>");
    SourceMgr.createMainFileIDForMemBuffer(membuffer);
    TheCompInst.getDiagnosticClient().BeginSourceFile(TheCompInst.getLangOpts(),&TheCompInst.getPreprocessor());
    Preprocessor &PP = TheCompInst.getPreprocessor();
    PP.getBuiltinInfo().InitializeBuiltins(PP.getIdentifierTable(),
                                           PP.getLangOpts());
                                           
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
    
    std::ostringstream out;
    out << std::string(membuffer->getBufferStart(),membuffer->getBufferEnd()) << "\n" 
    << "void __makeeverythinginclanglive_" << T->C->next_unused_id++ << "() {\n"
    << dummy.str() << "\n}\n";
    *output = out.str();
    //printf("output is %s\n",(*output).c_str());
}

static int dofile(terra_State * T, const char * code, const char ** argbegin, const char ** argend, Obj * result) {
    std::string buffer;
    dorewrite(T,code,argbegin,argend,&buffer,result);
    
    // CompilerInstance will hold the instance of the Clang compiler for us,
    // managing the various objects needed to run the compiler.
    CompilerInstance TheCompInst;
    TheCompInst.createDiagnostics(0, 0);
    
    CompilerInvocation::CreateFromArgs(TheCompInst.getInvocation(), argbegin, argend, TheCompInst.getDiagnostics());
    
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
    llvm::MemoryBuffer * membuffer = llvm::MemoryBuffer::getMemBufferCopy(buffer, "<buffer>");
    SourceMgr.createMainFileIDForMemBuffer(membuffer);
    TheCompInst.getDiagnosticClient().BeginSourceFile(TheCompInst.getLangOpts(),&TheCompInst.getPreprocessor());
    Preprocessor &PP = TheCompInst.getPreprocessor();
    PP.getBuiltinInfo().InitializeBuiltins(PP.getIdentifierTable(),
                                           PP.getLangOpts());
                                           
    CodeGenerator * codegen = CreateLLVMCodeGen(TheCompInst.getDiagnostics(), "mymodule", TheCompInst.getCodeGenOpts(), llvm::getGlobalContext() );

    ParseAST(TheCompInst.getPreprocessor(),
            codegen,
            TheCompInst.getASTContext());

    llvm::Module * mod = codegen->ReleaseModule();
    
    if(mod) {
        std::string err;
        DEBUG_ONLY(T) {
            mod->dump();
        }
        
        //cleanup after clang.
        //in some cases clang will mark stuff AvailableExternally (e.g. atoi on linux)
        //the linker will then delete it because it is not used.
        //switching it to WeakODR means that the linker will keep it even if it is not used
        for(llvm::Module::iterator it = mod->begin(), end = mod->end();
            it != end;
            ++it) {
            llvm::Function * fn = it;
            if(fn->hasAvailableExternallyLinkage()) {
                fn->setLinkage(llvm::GlobalValue::WeakODRLinkage);
            }
        }
        
        if(llvm::Linker::LinkModules(T->C->m, mod, 0, &err)) {
            terra_reporterror(T,"llvm: %s\n",err.c_str());
        }
        
    } else {
        terra_reporterror(T,"compilation of included c code failed\n");
    }
    
    delete codegen;
    //delete membuffer;
    
    return 0;
}

int include_c(lua_State * L) {
    terra_State * T = (terra_State*) lua_topointer(L,lua_upvalueindex(1));
    assert(T->L == L);
    const char * code = luaL_checkstring(L, -2);
    int N = lua_objlen(L, -1);
    std::vector<const char *> args;

    const char ** cpaths = clang_paths;
    while(*cpaths) {
        args.push_back(*cpaths);
        cpaths++;
    }
    
    args.push_back("-I");
    args.push_back(TERRA_CLANG_RESOURCE_DIRECTORY);
    
    for(int i = 0; i < N; i++) {
        lua_rawgeti(L, -1, i+1);
        args.push_back(luaL_checkstring(L,-1));
        lua_pop(L,1);
    }

    lua_newtable(L); //return a table of loaded functions
    int ref_table = lobj_newreftable(L);
    {
        Obj result;
        lua_pushvalue(L, -2);
        result.initFromStack(L, ref_table);
        
        dofile(T,code,&args[0],&args[args.size()],&result);
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
        if(!llvmfn) {
            std::stringstream ss;
            ss << "\x01_" << name;
            llvmfn = T->C->m->getFunction(ss.str());
        }
        assert(llvmfn);
        lua_pushlightuserdata(L, llvmfn);
        fn.setfield("llvm_function");
        void * fptr = T->C->ee->getPointerToFunction(llvmfn);
        lua_pushlightuserdata(L, fptr);
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