/* See Copyright Notice in ../LICENSE.txt */

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
#include <iostream>

#include "llvmheaders.h"
#include "clang/AST/Attr.h"
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
          resulttable(res),
          L(res->getState()),
          ref_table(res->getRefTable()) {
        
        //create tables for errors messages, general namespace, and the tagged namespace
        InitTable(&error_table,"errors");
        InitTable(&general,"general");
        InitTable(&tagged,"tagged");
    }
    void InitTable(Obj * tbl, const char * name) {
        lua_newtable(L);
        tbl->initFromStack(L, ref_table);
        tbl->push();
        resulttable->setfield(name);
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
    
    bool GetFields( RecordDecl * rd, Obj * entries) {
     
        //check the fields of this struct, if any one of them is not understandable, then this struct becomes 'opaque'
        //that is, we insert the type, and link it to its llvm type, so it can be used in terra code
        //but none of its fields are exposed (since we don't understand the layout)
        bool opaque = false;
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
            lua_newtable(L);
            fobj.push();
            lua_setfield(L,-2,"type");
            lua_pushstring(L,declstr.c_str());
            lua_setfield(L,-2,"field");
            entries->addentry();
        }
        return !opaque;

    }
    
    bool GetRecordTypeFromDecl(RecordDecl * rd, Obj * tt, std::string * fullname) {
        if(rd->isStruct() || rd->isUnion()) {
            std::string name = rd->getName();
            //TODO: why do some types not have names?
            Obj * thenamespace = &tagged;
            if(name == "") {
                TypedefNameDecl * decl = rd->getTypedefNameForAnonDecl();
                if(decl) {
                    thenamespace = &general;
                    name = decl->getName();
                } else {
                    name = "anon";
                }
            }

            assert(name != "");

            if(!thenamespace->obj(name.c_str(),tt)) {
                //create new blank struct, fill in with members
                std::stringstream ss;
                ss << (rd->isStruct() ? "struct." : "union.") << name;
                PushTypeFunction("getorcreatecstruct");
                lua_pushstring(L, name.c_str());
                lua_pushstring(L,ss.str().c_str());
                lua_call(L,2,1);
                tt->initFromStack(L,ref_table);
                tt->push();
                thenamespace->setfield(name.c_str()); //register the type (this prevents an infinite loop for recursive types)
            }
            
            if(tt->boolean("undefined") && rd->getDefinition() != NULL) {
                tt->clearfield("undefined");
                RecordDecl * defn = rd->getDefinition();
                Obj entries;
                tt->newlist(&entries);
                if(GetFields(defn, &entries)) {
                    if(!defn->isUnion()) {
                        //structtype.entries = {entry1, entry2, ... }
                        entries.push();
                        tt->setfield("entries");
                    } else {
                        //add as a union:
                        //structtype.entries = { {entry1,entry2,...} }
                        Obj allentries;
                        tt->obj("entries",&allentries);
                        entries.push();
                        allentries.addentry();
                    }
                }
            }
            
            if(fullname) {
                std::stringstream ss;
                if(thenamespace == &tagged)
                    ss << (rd->isStruct() ? "struct " : "union ");
                ss << name;
                *fullname = ss.str();
            }
            
            return true;
        } else {
            return ImportError("non-struct record types are not supported");
        }
    }

    bool GetType(QualType T, Obj * tt) {
        
        T = Context->getCanonicalType(T);
        const Type *Ty = T.getTypePtr();
        
        switch (Ty->getTypeClass()) {
          case Type::Record: {
            const RecordType *RT = dyn_cast<RecordType>(Ty);
            RecordDecl * rd = RT->getDecl();
            return GetRecordTypeFromDecl(rd, tt,NULL);
          }  break; //TODO
          case Type::Builtin:
            switch (cast<BuiltinType>(Ty)->getKind()) {
            case BuiltinType::Void:
              InitType("opaque",tt);
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
    void KeepTypeLive(llvm::StringRef name) {
         //make sure it stays live through llvm translation
        output << "(void)(" << name.str() << "*) (void*) 0;\n";
    }
    bool VisitTypedefDecl(TypedefDecl * TD) {
        if(TD == TD->getCanonicalDecl() && TD->getDeclContext()->getDeclKind() == Decl::TranslationUnit) {
            llvm::StringRef name = TD->getName();
            QualType QT = Context->getCanonicalType(TD->getUnderlyingType());
            Obj typ;
            if(GetType(QT,&typ)) {
                typ.push();
                general.setfield(name.str().c_str());
               KeepTypeLive(name);
            } else {
                SetErrorReport(name.str().c_str());
            }
        }
        return true;
    }
    bool VisitRecordDecl(RecordDecl * rd) {
        if(rd->getDeclContext()->getDeclKind() == Decl::TranslationUnit) {
            Obj type;
            std::string name;
            if(GetRecordTypeFromDecl(rd, &type,&name)) {
                KeepTypeLive(name);
            }
        }
        return true;
    }
    
    bool GetFuncType(const FunctionType * f, Obj * typ) {
        Obj returns,parameters;
        resulttable->newlist(&returns);
        resulttable->newlist(&parameters);
        
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
       
        
        const FunctionProtoType * proto = f->getAs<FunctionProtoType>();
        //proto is null if the function was declared without an argument list (e.g. void foo() and not void foo(void))
        //we don't support old-style C parameter lists, we just treat them as empty
        if(proto) {
            for(size_t i = 0; i < proto->getNumArgs(); i++) {
                QualType PT = proto->getArgType(i);
                Obj pt;
                if(!GetType(PT,&pt)) {
                    valid = false; //keep going with attempting to parse type to make sure we see all the reasons why we cannot support this function
                } else if(valid) {
                    pt.push();
                    parameters.addentry();
                }
            }
        }
        
        if(valid) {
            PushTypeFunction("functype");
            parameters.push();
            returns.push();
            lua_pushboolean(L, proto ? proto->isVariadic() : false);
            lua_call(L, 3, 1);
            typ->initFromStack(L,ref_table);
        }
        
        return valid;
    }
    bool VisitFunctionDecl(FunctionDecl *f) {
         // Function name
        DeclarationName DeclName = f->getNameInfo().getName();
        std::string FuncName = DeclName.getAsString();
        const FunctionType * fntyp = f->getType()->getAs<FunctionType>();
        
        if(!fntyp)
            return true;
        
        if(f->getStorageClass() == clang::SC_Static) {
            ImportError("cannot import static functions.");
            SetErrorReport(FuncName.c_str());
            return true;
        }
        
        Obj typ;
        if(!GetFuncType(fntyp,&typ)) {
            SetErrorReport(FuncName.c_str());
            return true;
        }
        std::string InternalName = FuncName;
        AsmLabelAttr * asmlabel = f->getAttr<AsmLabelAttr>();
        if(asmlabel) {
            InternalName = asmlabel->getLabel();
            #ifndef __linux__
                //In OSX and Windows LLVM mangles assembler labels by adding a '\01' prefix
                InternalName.insert(InternalName.begin(), '\01');
            #endif
        }
        CreateFunction(FuncName,InternalName,&typ);
        
        //make sure this function is live in codegen by creating a dummy reference to it (void) is to suppress unused warnings
        output << "    (void)" << FuncName << ";\n";         
        
        return true;
    }
    void CreateFunction(const std::string & name, const std::string & internalname, Obj * typ) {
        lua_getfield(L, LUA_GLOBALSINDEX, "terra");
        lua_getfield(L, -1, "newcfunction");
        lua_remove(L,-2); //terra table
        lua_pushstring(L, internalname.c_str());
        typ->push();
        lua_call(L, 2, 1);
        general.setfield(name.c_str());
    }
    void SetContext(ASTContext * ctx) {
        Context = ctx;
    }
  private:
    std::stringstream & output;
    Rewriter &TheRewriter;
    Obj * resulttable; //holds table returned to lua includes "functions", "types", and "errors"
    lua_State * L;
    int ref_table;
    ASTContext * Context;
    Obj error_table; //name -> related error message
    Obj general; //name -> function or type in the general namespace
    Obj tagged; //name -> type in the tagged namespace (e.g. struct Foo)
    
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

static void initializeclang(terra_State * T, llvm::MemoryBuffer * membuffer, const char ** argbegin, const char ** argend, CompilerInstance * TheCompInst) {
    // CompilerInstance will hold the instance of the Clang compiler for us,
    // managing the various objects needed to run the compiler.
    #if defined LLVM_3_1 || defined LLVM_3_2
    TheCompInst->createDiagnostics(0, 0);
    #else
    TheCompInst->createDiagnostics();
    #endif
    
    CompilerInvocation::CreateFromArgs(TheCompInst->getInvocation(), argbegin, argend, TheCompInst->getDiagnostics());
    //need to recreate the diagnostics engine so that it actually listens to warning flags like -Wno-deprecated
    //this cannot go before CreateFromArgs
    #if defined LLVM_3_1 || defined LLVM_3_2
    TheCompInst->createDiagnostics(argbegin - argend, argbegin);
    TargetOptions & to = TheCompInst->getTargetOpts();
    #else
    TheCompInst->createDiagnostics();
    TargetOptions * to = &TheCompInst->getTargetOpts();
    #endif
    
    TargetInfo *TI = TargetInfo::CreateTargetInfo(TheCompInst->getDiagnostics(), to);
    TheCompInst->setTarget(TI);
    
    TheCompInst->createFileManager();
    FileManager &FileMgr = TheCompInst->getFileManager();
    TheCompInst->createSourceManager(FileMgr);
    SourceManager &SourceMgr = TheCompInst->getSourceManager();
    TheCompInst->createPreprocessor();
    TheCompInst->createASTContext();

    // Set the main file handled by the source manager to the input file.
    SourceMgr.createMainFileIDForMemBuffer(membuffer);
    TheCompInst->getDiagnosticClient().BeginSourceFile(TheCompInst->getLangOpts(),&TheCompInst->getPreprocessor());
    Preprocessor &PP = TheCompInst->getPreprocessor();
    PP.getBuiltinInfo().InitializeBuiltins(PP.getIdentifierTable(),
                                           PP.getLangOpts());
    
}

static void dorewrite(terra_State * T, const char * code, const char ** argbegin, const char ** argend, std::string * output, Obj * result) {
    
    llvm::MemoryBuffer * membuffer = llvm::MemoryBuffer::getMemBufferCopy(code, "<buffer>");
    CompilerInstance TheCompInst;
    initializeclang(T, membuffer, argbegin, argend, &TheCompInst);
    
    // Create an AST consumer instance which is going to get called by
    // ParseAST.
    // A Rewriter helps us manage the code rewriting task.
    SourceManager & SourceMgr = TheCompInst.getSourceManager();
    Rewriter TheRewriter;
    TheRewriter.setSourceMgr(SourceMgr, TheCompInst.getLangOpts());
    
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
    llvm::MemoryBuffer * membuffer = llvm::MemoryBuffer::getMemBufferCopy(buffer, "<buffer>");
    initializeclang(T, membuffer, argbegin, argend, &TheCompInst);
    
    #if defined LLVM_3_1 || defined LLVM_3_2
    CodeGenerator * codegen = CreateLLVMCodeGen(TheCompInst.getDiagnostics(), "mymodule", TheCompInst.getCodeGenOpts(), *T->C->ctx );
    #else
    CodeGenerator * codegen = CreateLLVMCodeGen(TheCompInst.getDiagnostics(), "mymodule", TheCompInst.getCodeGenOpts(), TheCompInst.getTargetOpts(), *T->C->ctx );
    #endif
    
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

#ifdef _WIN32
	args.push_back("-fms-extensions");
	args.push_back("-fms-compatibility");
#define __stringify(x) #x
#define __indirect(x) __stringify(x)
	args.push_back("-fmsc-version=" __indirect(_MSC_VER));
#endif
    
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
