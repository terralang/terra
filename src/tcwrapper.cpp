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
#include "tllvmutil.h"
#include "llvm/Support/Errc.h"
#include "llvm/Option/ArgList.h"
#include "clang/AST/Attr.h"
#include "clang/Lex/LiteralSupport.h"
#include "clang/Driver/Driver.h"
#include "clang/Driver/Compilation.h"
#include "clang/Driver/ToolChain.h"
#include "clang/Basic/Builtins.h"
#include "tcompilerstate.h"

using namespace clang;

static void CreateTableWithName(Obj *parent, const char *name, Obj *result) {
    lua_State *L = parent->getState();
    lua_newtable(L);
    result->initFromStack(L, parent->getRefTable());
    result->push();
    parent->setfield(name);
}

const int TARGET_POS = 1;
const int HEADERPROVIDER_POS = 4;

// part of the setup is adapted from:
// http://eli.thegreenplace.net/2012/06/08/basic-source-to-source-transformation-with-clang/
// By implementing RecursiveASTVisitor, we can specify which AST nodes
// we're interested in by overriding relevant methods.
class IncludeCVisitor : public RecursiveASTVisitor<IncludeCVisitor> {
public:
    IncludeCVisitor(Obj *res, TerraTarget *TT_, const std::string &livenessfunction_)
            : resulttable(res),
              L(res->getState()),
              ref_table(res->getRefTable()),
              TT(TT_),
              livenessfunction(livenessfunction_) {
        // create tables for errors messages, general namespace, and the tagged namespace
        InitTable(&error_table, "errors");
        InitTable(&general, "general");
        InitTable(&tagged, "tagged");
    }
    void InitTable(Obj *tbl, const char *name) {
        CreateTableWithName(resulttable, name, tbl);
    }

    void InitType(const char *name, Obj *tt) {
        PushTypeField(name);
        tt->initFromStack(L, ref_table);
    }

    void PushTypeField(const char *name) {
        lua_getfield(L, LUA_GLOBALSINDEX, "terra");
        lua_getfield(L, -1, "types");
        lua_getfield(L, -1, name);
        lua_remove(L, -2);
        lua_remove(L, -2);
    }

    bool ImportError(const std::string &msg) {
        error_message = msg;
        return false;
    }

    bool GetFields(RecordDecl *rd, Obj *entries) {
        // check the fields of this struct, if any one of them is not understandable, then
        // this struct becomes 'opaque' that is, we insert the type, and link it to its
        // llvm type, so it can be used in terra code but none of its fields are exposed
        // (since we don't understand the layout)
        bool opaque = false;
        int anonname = 0;
        for (RecordDecl::field_iterator it = rd->field_begin(), end = rd->field_end();
             it != end; ++it) {
            DeclarationName declname = it->getDeclName();

            if (it->isBitField() || (!it->isAnonymousStructOrUnion() && !declname)) {
                opaque = true;
                continue;
            }
            std::string declstr;
            if (it->isAnonymousStructOrUnion()) {
                char buf[32];
                snprintf(buf, sizeof(buf), "_%d", anonname++);
                declstr = buf;
            } else {
                declstr = declname.getAsString();
            }
            QualType FT = it->getType();
            Obj fobj;
            if (!GetType(FT, &fobj)) {
                opaque = true;
                continue;
            }
            lua_newtable(L);
            fobj.push();
            lua_setfield(L, -2, "type");
            lua_pushstring(L, declstr.c_str());
            lua_setfield(L, -2, "field");
            entries->addentry();
        }
        return !opaque;
    }
    size_t RegisterRecordType(QualType T) {
        outputtypes.push_back(Context->getPointerType(T));
        assert(outputtypes.size() < 65536 &&
               "fixme: clang limits number of arguments to 65536");
        return outputtypes.size() - 1;
    }
    bool GetRecordTypeFromDecl(RecordDecl *rd, Obj *tt) {
        if (rd->isStruct() || rd->isUnion()) {
            std::string name = rd->getName().str();
            Obj *thenamespace = &tagged;
            if (name == "") {
                TypedefNameDecl *decl = rd->getTypedefNameForAnonDecl();
                if (decl) {
                    thenamespace = &general;
                    name = decl->getName().str();
                }
            }
            // if name == "" then we have an anonymous struct
            if (!thenamespace->obj(name.c_str(), tt)) {
                lua_getfield(L, TARGET_POS, "getorcreatecstruct");
                lua_pushvalue(L, TARGET_POS);
                lua_pushstring(L, name.c_str());
                lua_pushboolean(L, thenamespace == &tagged);
                lua_call(L, 3, 1);
                tt->initFromStack(L, ref_table);
                if (!tt->boolean("llvm_definingfunction")) {
                    size_t argpos = RegisterRecordType(Context->getRecordType(rd));
                    lua_pushstring(L, livenessfunction.c_str());
                    tt->setfield("llvm_definingfunction");
                    lua_pushinteger(L, TT->id);
                    tt->setfield("llvm_definingtarget");
                    lua_pushinteger(L, argpos);
                    tt->setfield("llvm_argumentposition");
                }
                if (name != "") {  // do not remember a name for an anonymous struct
                    tt->push();
                    thenamespace->setfield(name.c_str());  // register the type
                }
            }

            if (tt->boolean("undefined") && rd->getDefinition() != NULL) {
                tt->clearfield("undefined");
                RecordDecl *defn = rd->getDefinition();
                Obj entries;
                tt->newlist(&entries);
                if (GetFields(defn, &entries)) {
                    if (!defn->isUnion()) {
                        // structtype.entries = {entry1, entry2, ... }
                        entries.push();
                        tt->setfield("entries");
                    } else {
                        // add as a union:
                        // structtype.entries = { {entry1,entry2,...} }
                        Obj allentries;
                        tt->obj("entries", &allentries);
                        entries.push();
                        allentries.addentry();
                    }
                    tt->pushfield("complete");
                    tt->push();
                    lua_call(L, 1, 0);
                }
            }

            return true;
        } else {
            return ImportError("non-struct record types are not supported");
        }
    }

    bool GetType(QualType T, Obj *tt) {
        T = Context->getCanonicalType(T);
        const Type *Ty = T.getTypePtr();

        switch (Ty->getTypeClass()) {
            case Type::Record: {
                const RecordType *RT = dyn_cast<RecordType>(Ty);
                RecordDecl *rd = RT->getDecl();
                return GetRecordTypeFromDecl(rd, tt);
            } break;  // TODO
            case Type::Builtin:
                switch (cast<BuiltinType>(Ty)->getKind()) {
                    case BuiltinType::Void:
                        InitType("opaque", tt);
                        return true;
                    case BuiltinType::Bool:
                        InitType("bool", tt);
                        return true;
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
                        if (Ty->isUnsignedIntegerType()) ss << "u";
                        ss << "int";
                        int sz = Context->getTypeSize(T);
                        ss << sz;
                        InitType(ss.str().c_str(), tt);
                        return true;
                    }
                    case BuiltinType::Half:
                        break;
                    case BuiltinType::Float:
                        InitType("float", tt);
                        return true;
                    case BuiltinType::Double:
                        InitType("double", tt);
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
                if (!GetType(ETy, &t2)) {
                    return false;
                }
                PushTypeField("pointer");
                t2.push();
                lua_call(L, 1, 1);
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
                if (GetType(ATy->getElementType(), &at)) {
                    PushTypeField("array");
                    at.push();
                    lua_pushinteger(L, sz);
                    lua_call(L, 2, 1);
                    tt->initFromStack(L, ref_table);
                    return true;
                } else {
                    return false;
                }
            } break;
            case Type::ExtVector:
            case Type::Vector: {
                // printf("making a vector!\n");
                const VectorType *VT = cast<VectorType>(T);
                Obj at;
                if (GetType(VT->getElementType(), &at)) {
                    int n = VT->getNumElements();
                    PushTypeField("vector");
                    at.push();
                    lua_pushinteger(L, n);
                    lua_call(L, 2, 1);
                    tt->initFromStack(L, ref_table);
                    return true;
                } else {
                    return false;
                }
            } break;
            case Type::FunctionNoProto: /* fallthrough */
            case Type::FunctionProto: {
                const FunctionType *FT = cast<FunctionType>(Ty);
                return FT && GetFuncType(FT, tt);
            }
            case Type::ObjCObject:
            case Type::ObjCInterface:
            case Type::ObjCObjectPointer:
            case Type::Enum:
                InitType("uint32", tt);
                return true;
            case Type::BlockPointer:
            case Type::MemberPointer:
            case Type::Atomic:
            default:
                break;
        }
        std::stringstream ss;
        ss << "type not understood: " << T.getAsString().c_str() << " "
           << Ty->getTypeClass();
        return ImportError(ss.str().c_str());
    }
    void SetErrorReport(const char *field) {
        lua_pushstring(L, error_message.c_str());
        error_table.setfield(field);
    }
    CStyleCastExpr *CreateCast(QualType Ty, CastKind Kind, Expr *E) {
        TypeSourceInfo *TInfo = Context->getTrivialTypeSourceInfo(Ty, SourceLocation());
#if LLVM_VERSION < 120
        return CStyleCastExpr::Create(*Context, Ty, VK_RValue, Kind, E, 0, TInfo,
                                      SourceLocation(), SourceLocation());
#elif LLVM_VERSION < 130
        return CStyleCastExpr::Create(*Context, Ty, VK_RValue, Kind, E, 0,
                                      FPOptionsOverride::getFromOpaqueInt(0), TInfo,
                                      SourceLocation(), SourceLocation());
#else
        return CStyleCastExpr::Create(*Context, Ty, VK_PRValue, Kind, E, 0,
                                      FPOptionsOverride::getFromOpaqueInt(0), TInfo,
                                      SourceLocation(), SourceLocation());
#endif
    }
    IntegerLiteral *LiteralZero() {
        unsigned IntSize = static_cast<unsigned>(Context->getTypeSize(Context->IntTy));
        return IntegerLiteral::Create(*Context, llvm::APInt(IntSize, 0), Context->IntTy,
                                      SourceLocation());
    }
    DeclRefExpr *GetDeclReference(ValueDecl *vd) {
        DeclRefExpr *DR = DeclRefExpr::Create(*Context, NestedNameSpecifierLoc(),
                                              SourceLocation(), vd, false,
                                              SourceLocation(), vd->getType(), VK_LValue);
        return DR;
    }
    void KeepLive(ValueDecl *vd) {
        Expr *castexp =
                CreateCast(Context->VoidTy, clang::CK_ToVoid, GetDeclReference(vd));
        outputstmts.push_back(castexp);
    }
    bool VisitTypedefDecl(TypedefDecl *TD) {
        bool isCanonical = (TD == TD->getCanonicalDecl());
#if defined(_WIN32)
        // Starting with LLVM 3.6, clang initializes "size_t" as an implicit declaration
        // when being compatible with MSVC.
        if (!isCanonical && TD->getName().str() == "size_t") {
            isCanonical = (TD->getPreviousDecl() == TD->getCanonicalDecl());
        }
#endif
        if (isCanonical && TD->getDeclContext()->getDeclKind() == Decl::TranslationUnit) {
            llvm::StringRef name = TD->getName();
            QualType QT = Context->getCanonicalType(TD->getUnderlyingType());
            Obj typ;
            if (GetType(QT, &typ)) {
                typ.push();
                general.setfield(name.str().c_str());
            } else {
                SetErrorReport(name.str().c_str());
            }
        }
        return true;
    }
    bool TraverseRecordDecl(RecordDecl *rd) {
        if (rd->getDeclContext()->getDeclKind() == Decl::TranslationUnit) {
            Obj type;
            GetRecordTypeFromDecl(rd, &type);
        }
        return true;
    }
    bool VisitEnumConstantDecl(EnumConstantDecl *E) {
        int64_t v = E->getInitVal().getSExtValue();
        llvm::StringRef name = E->getName();
        lua_pushnumber(L, (double)v);  // I _think_ enums by spec must fit in an int, so
                                       // they will fit in a double
        general.setfield(name.str().c_str());
        return true;
    }
    bool GetFuncType(const FunctionType *f, Obj *typ) {
        Obj returntype, parameters;
        resulttable->newlist(&parameters);

        bool valid =
                true;  // decisions about whether this function can be exported or not are
                       // delayed until we have seen all the potential problems
        QualType RT = f->getReturnType();
        if (RT->isVoidType()) {
            PushTypeField("unit");
            returntype.initFromStack(L, ref_table);
        } else {
            if (!GetType(RT, &returntype)) valid = false;
        }

        const FunctionProtoType *proto = f->getAs<FunctionProtoType>();
        // proto is null if the function was declared without an argument list (e.g. void
        // foo() and not void foo(void)) we don't support old-style C parameter lists, we
        // just treat them as empty
        if (proto) {
            for (size_t i = 0; i < proto->getNumParams(); i++) {
                QualType PT = proto->getParamType(i);
                Obj pt;
                if (!GetType(PT, &pt)) {
                    valid = false;  // keep going with attempting to parse type to make
                                    // sure we see all the reasons why we cannot support
                                    // this function
                } else if (valid) {
                    pt.push();
                    parameters.addentry();
                }
            }
        }

        if (valid) {
            PushTypeField("functype");
            parameters.push();
            returntype.push();
            lua_pushboolean(L, proto ? proto->isVariadic() : false);
            lua_call(L, 3, 1);
            typ->initFromStack(L, ref_table);
        }

        return valid;
    }
    bool TraverseFunctionDecl(FunctionDecl *f) {
        // Function name
        DeclarationName DeclName = f->getNameInfo().getName();
        std::string FuncName = DeclName.getAsString();
        const FunctionType *fntyp = f->getType()->getAs<FunctionType>();

        if (!fntyp) return true;

        if (f->getStorageClass() == clang::SC_Static) {
            ImportError("cannot import static functions.");
            SetErrorReport(FuncName.c_str());
            return true;
        }

        Obj typ;
        if (!GetFuncType(fntyp, &typ)) {
            SetErrorReport(FuncName.c_str());
            return true;
        }
        std::string InternalName = FuncName;

        // Avoid mangle on LLVM 6 and macOS
        AsmLabelAttr *asmlabel = f->getAttr<AsmLabelAttr>();
        if (asmlabel) {
#if !defined(__APPLE__)
            InternalName = asmlabel->getLabel().str();
#if !defined(__linux__) && !defined(__FreeBSD__)
            // In OSX and Windows LLVM mangles assembler labels by adding a '\01' prefix
            InternalName.insert(InternalName.begin(), '\01');
#endif
#else
            std::string label = asmlabel->getLabel().str();
            if (!((label[0] == '_') && (label.substr(1) == InternalName))) {
                InternalName = asmlabel->getLabel().str();
                InternalName.insert(InternalName.begin(), '\01');
            }
#endif
            // Uncomment for mangling issue debugging
            // llvm::errs() << "[mangle] " << FuncName << "=" << InternalName << "\n";
        }

        CreateFunction(FuncName, InternalName, &typ);

        KeepLive(f);  // make sure this function is live in codegen by creating a dummy
                      // reference to it (void) is to suppress unused warnings

        return true;
    }
    void CreateFunction(const std::string &name, const std::string &internalname,
                        Obj *typ) {
        if (!general.hasfield(name.c_str())) {
            lua_getfield(L, LUA_GLOBALSINDEX, "terra");
            lua_getfield(L, -1, "externfunction");
            lua_remove(L, -2);  // terra table
            lua_pushstring(L, internalname.c_str());
            typ->push();
            lua_call(L, 2, 1);
            general.setfield(name.c_str());
        }
    }
    void SetContext(ASTContext *ctx) { Context = ctx; }
    FunctionDecl *GetLivenessFunction() {
        IdentifierInfo &II = Context->Idents.get(livenessfunction);
        DeclarationName N = Context->DeclarationNames.getIdentifier(&II);
        QualType T = Context->getFunctionType(Context->VoidTy, outputtypes,
                                              FunctionProtoType::ExtProtoInfo());
        FunctionDecl *F = FunctionDecl::Create(
                *Context, Context->getTranslationUnitDecl(), SourceLocation(),
                SourceLocation(), N, T, 0, SC_Extern);

        std::vector<ParmVarDecl *> params;
        for (size_t i = 0; i < outputtypes.size(); i++) {
            params.push_back(ParmVarDecl::Create(*Context, F, SourceLocation(),
                                                 SourceLocation(), 0, outputtypes[i],
                                                 /*TInfo=*/0, SC_None, 0));
        }
        F->setParams(params);
        CompoundStmt *stmts = CompoundStmt::Create(*Context, outputstmts,
#if LLVM_VERSION >= 150
                                                   FPOptionsOverride(),
#endif
                                                   SourceLocation(), SourceLocation());
        F->setBody(stmts);
        return F;
    }
    bool TraverseVarDecl(VarDecl *v) {
        if (!(v->isFileVarDecl() &&
              (v->hasExternalStorage() ||
               v->getStorageClass() ==
                       clang::SC_None)))  // is this a non-static global variable?
            return true;

        QualType t = v->getType();
        Obj typ;

        if (!GetType(t, &typ)) return true;

        std::string name = v->getNameAsString();
        CreateExternGlobal(name, &typ);
        KeepLive(v);

        return true;
    }
    void CreateExternGlobal(const std::string &name, Obj *typ) {
        if (!general.hasfield(name.c_str())) {
            lua_getfield(L, LUA_GLOBALSINDEX, "terra");
            lua_getfield(L, -1, "global");
            lua_remove(L, -2);  // terra table
            typ->push();
            lua_pushnil(L);  // no initializer
            lua_pushstring(L, name.c_str());
            lua_pushboolean(L, true);
            lua_call(L, 4, 1);
            general.setfield(name.c_str());
        }
    }

private:
    std::vector<Stmt *> outputstmts;
    std::vector<QualType> outputtypes;
    Obj *resulttable;  // holds table returned to lua includes "functions", "types", and
                       // "errors"
    lua_State *L;
    int ref_table;
    ASTContext *Context;
    Obj error_table;  // name -> related error message
    Obj general;      // name -> function or type in the general namespace
    Obj tagged;       // name -> type in the tagged namespace (e.g. struct Foo)
    std::string error_message;
    TerraTarget *TT;
    std::string livenessfunction;
};

class CodeGenProxy : public ASTConsumer {
public:
    CodeGenProxy(CodeGenerator *CG_, Obj *result, TerraTarget *TT,
                 const std::string &livenessfunction)
            : CG(CG_), Visitor(result, TT, livenessfunction) {}
    CodeGenerator *CG;
    IncludeCVisitor Visitor;
    virtual ~CodeGenProxy() {}
    virtual void Initialize(ASTContext &Context) {
        Visitor.SetContext(&Context);
        CG->Initialize(Context);
    }
    virtual bool HandleTopLevelDecl(DeclGroupRef D) {
        for (DeclGroupRef::iterator b = D.begin(), e = D.end(); b != e; ++b)
            Visitor.TraverseDecl(*b);
        return CG->HandleTopLevelDecl(D);
    }
    virtual void HandleInterestingDecl(DeclGroupRef D) { CG->HandleInterestingDecl(D); }
    virtual void HandleTranslationUnit(ASTContext &Ctx) {
        Decl *Decl = Visitor.GetLivenessFunction();
        DeclGroupRef R = DeclGroupRef::Create(Ctx, &Decl, 1);
        CG->HandleTopLevelDecl(R);
        CG->HandleTranslationUnit(Ctx);
    }
    virtual void HandleTagDeclDefinition(TagDecl *D) { CG->HandleTagDeclDefinition(D); }
    virtual void HandleCXXImplicitFunctionInstantiation(FunctionDecl *D) {
        CG->HandleCXXImplicitFunctionInstantiation(D);
    }
    virtual void HandleTopLevelDeclInObjCContainer(DeclGroupRef D) {
        CG->HandleTopLevelDeclInObjCContainer(D);
    }
    virtual void CompleteTentativeDefinition(VarDecl *D) {
        CG->CompleteTentativeDefinition(D);
    }
    virtual void HandleCXXStaticMemberVarInstantiation(VarDecl *D) {
        CG->HandleCXXStaticMemberVarInstantiation(D);
    }
    virtual void HandleVTable(CXXRecordDecl *RD) { CG->HandleVTable(RD); }
    virtual ASTMutationListener *GetASTMutationListener() {
        return CG->GetASTMutationListener();
    }
    virtual ASTDeserializationListener *GetASTDeserializationListener() {
        return CG->GetASTDeserializationListener();
    }
    virtual void PrintStats() { CG->PrintStats(); }

    virtual void HandleImplicitImportDecl(ImportDecl *D) {
        CG->HandleImplicitImportDecl(D);
    }
    virtual bool shouldSkipFunctionBody(Decl *D) { return CG->shouldSkipFunctionBody(D); }
};

class LuaProvidedFile : public llvm::vfs::File {
private:
    std::string Name;
    llvm::vfs::Status Status;
    StringRef Buffer;

public:
    LuaProvidedFile(const std::string &Name_, const llvm::vfs::Status &Status_,
                    const StringRef &Buffer_)
            : Name(Name_), Status(Status_), Buffer(Buffer_) {}
    virtual ~LuaProvidedFile() override {}
    virtual llvm::ErrorOr<llvm::vfs::Status> status() override { return Status; }
    virtual llvm::ErrorOr<std::unique_ptr<llvm::MemoryBuffer>> getBuffer(
            const Twine &Name, int64_t FileSize, bool RequiresNullTerminator,
            bool IsVolatile) override {
        return llvm::MemoryBuffer::getMemBuffer(Buffer, "", RequiresNullTerminator);
    }
    virtual std::error_code close() override { return std::error_code(); }
};

static llvm::sys::TimePoint<> ZeroTime() {
    return llvm::sys::TimePoint<>(std::chrono::nanoseconds::zero());
}

class LuaOverlayFileSystem : public llvm::vfs::FileSystem {
private:
    IntrusiveRefCntPtr<llvm::vfs::FileSystem> RFS;
    lua_State *L;

public:
    LuaOverlayFileSystem(lua_State *L_) : RFS(llvm::vfs::getRealFileSystem()), L(L_) {}

    bool GetFile(const llvm::Twine &Path, llvm::vfs::Status *status,
                 StringRef *contents) {
        lua_pushvalue(L, HEADERPROVIDER_POS);
        lua_pushstring(L, Path.str().c_str());
        lua_call(L, 1, 1);
        if (!lua_istable(L, -1)) {
            lua_pop(L, 1);
            return false;
        }
        llvm::sys::fs::file_type filetype = llvm::sys::fs::file_type::directory_file;
        int64_t size = 0;
        lua_getfield(L, -1, "kind");
        const char *kind = lua_tostring(L, -1);
        if (strcmp(kind, "file") == 0) {
            filetype = llvm::sys::fs::file_type::regular_file;
            lua_getfield(L, -2, "contents");
            const char *data = (const char *)lua_touserdata(L, -1);
            if (!data) {
                data = lua_tostring(L, -1);
            }
            if (!data) {
                lua_pop(L, 3);  // pop table,kind,contents
                return false;
            }
            lua_getfield(L, -3, "size");
            size = (lua_isnumber(L, -1)) ? lua_tonumber(L, -1) : ::strlen(data);
            *contents = StringRef(data, size);
            lua_pop(L, 2);  // pop contents, size
        }
        *status = llvm::vfs::Status(Path.str(), llvm::vfs::getNextVirtualUniqueID(),
                                    ZeroTime(), 0, 0, size, filetype,
                                    llvm::sys::fs::all_all);
        lua_pop(L, 2);  // pop table, kind
        return true;
    }
    virtual ~LuaOverlayFileSystem() {}

    virtual llvm::ErrorOr<llvm::vfs::Status> status(const llvm::Twine &Path) override {
        static const std::error_code noSuchFileErr =
                std::make_error_code(std::errc::no_such_file_or_directory);
        llvm::ErrorOr<llvm::vfs::Status> RealStatus = RFS->status(Path);
        if (RealStatus || RealStatus.getError() != noSuchFileErr) return RealStatus;
        llvm::vfs::Status Status;
        StringRef Buffer;
        if (GetFile(Path, &Status, &Buffer)) {
            return Status;
        }
        return llvm::errc::no_such_file_or_directory;
    }

    virtual llvm::ErrorOr<std::unique_ptr<llvm::vfs::File>> openFileForRead(
            const llvm::Twine &Path) override {
        llvm::ErrorOr<std::unique_ptr<llvm::vfs::File>> ec = RFS->openFileForRead(Path);
        if (ec || ec.getError() != llvm::errc::no_such_file_or_directory) return ec;
        llvm::vfs::Status Status;
        StringRef Buffer;
        if (GetFile(Path, &Status, &Buffer)) {
            return std::unique_ptr<llvm::vfs::File>(
                    new LuaProvidedFile(Path.str(), Status, Buffer));
        }
        return llvm::errc::no_such_file_or_directory;
    }

    virtual llvm::vfs::directory_iterator dir_begin(const llvm::Twine &Dir,
                                                    std::error_code &EC) override {
        printf("BUGBUG: unexpected call to directory iterator in C header include. "
               "report this a bug on github.com/terralang/terra");
        // as far as I can tell this isn't used by the things we are using, so
        // I am leaving it unfinished until this changes.
        return RFS->dir_begin(Dir, EC);
    }

    llvm::ErrorOr<std::string> getCurrentWorkingDirectory() const override {
        return std::string("cwd");
    }
    std::error_code setCurrentWorkingDirectory(const Twine &Path) override {
        return std::error_code();
    }
};

// Clang's initialization happens in two phases:
//
//  1. Driver::BuildCompilation builds a set of jobs that represent
//     different actions the compiler would need to
//     perform. Historically, these would have literally been
//     different processes. (Remember cc1?) Now they're all in the
//     same process but Clang still has to be reinitialized for each
//     phase of the computation.
//
//  2. CompilerInvocation::CreateFromArgs initializes a specific
//     invocation of Clang. This is what you'd normally think of as
//     the compiler frontend and does all the heavily lifting to
//     actually compile code.
//
// For <reasons>, some of Clang's defaults are set in (1) and not
// (2). This makes it literally impossible to correctly initialize
// Clang in some scenarios with (2) alone. Of course, because we're
// using Clang as a JIT, we cannot simply execute the jobs created
// when we call (1). Instead, we have to call (1), extract what we
// need, and pass that ourselves to (2).
//
// This function does the first part of this process. While (1) sets a
// lot of flags, it seems to be sufficient to extract two main sets:
//
//  * Header search options. Needed to get any sort of sane header
//    search behavior on Windows.
//
//  * Target ABI. Needed on macOS M1 or else Clang will miscompile
//    varargs code.
void InitHeaderSearchFlagsAndArgs(std::string const &TripleStr, HeaderSearchOptions &HSO,
                                  std::vector<std::string> &ExtraArgs) {
    using namespace llvm::sys;

    IntrusiveRefCntPtr<DiagnosticIDs> DiagID(new DiagnosticIDs());
    IntrusiveRefCntPtr<DiagnosticOptions> DiagOpts(new DiagnosticOptions());
    auto *DiagsBuffer = new IgnoringDiagConsumer();
    std::unique_ptr<DiagnosticsEngine> Diags(
            new DiagnosticsEngine(DiagID, &*DiagOpts, DiagsBuffer));

    auto argslist = {"dummy",
                     "-x",
                     "c",
                     "-",
                     "-target",
                     TripleStr.c_str(),
                     "-resource-dir",
                     HSO.ResourceDir.c_str()};
    SmallVector<const char *, 5> Args(argslist.begin(), argslist.end());

    // Build a dummy compilation to obtain the current toolchain.
    // Indeed, the BuildToolchain function of clang::driver::Driver is private :/
    clang::driver::Driver D("dummy", TripleStr, *Diags);
    std::unique_ptr<driver::Compilation> C(D.BuildCompilation(Args));

    // Extract the target ABI from the CC1 job.
    for (auto &j : C->getJobs()) {
        auto &args = j.getArguments();
        if (strcmp(args[0], "-cc1") == 0) {
            for (auto arg = args.begin(), arg_end = args.end(); arg != arg_end; ++arg) {
                if (strcmp(*arg, "-target-abi") == 0 && arg + 1 != arg_end) {
                    ExtraArgs.emplace_back(*arg);
                    ExtraArgs.emplace_back(*++arg);
                }
            }
        }
    }

    clang::driver::ToolChain const &TC = C->getDefaultToolChain();

    llvm::opt::ArgStringList IncludeArgs;
    TC.AddClangSystemIncludeArgs(C->getArgs(), IncludeArgs);

    TC.AddCudaIncludeArgs(C->getArgs(), IncludeArgs);

    // organized in pairs "-<flag> <directory>"
    assert(((IncludeArgs.size() & 1) == 0) && "even number of IncludeArgs");
    HSO.UserEntries.reserve(IncludeArgs.size() / 2);
    for (size_t i = 0; i != IncludeArgs.size(); i += 2) {
        auto &Directory = IncludeArgs[i + 1];

        auto IncludeType = frontend::System;
        if (IncludeArgs[i] == StringRef("-internal-externc-isystem"))
            IncludeType = frontend::ExternCSystem;

        HSO.UserEntries.emplace_back(Directory, IncludeType, false, false);
    }
}

static void initializeclang(terra_State *T, llvm::MemoryBuffer *membuffer,
                            const std::vector<const char *> &args,
                            CompilerInstance *TheCompInst,
                            llvm::IntrusiveRefCntPtr<llvm::vfs::FileSystem> FS) {
    // CompilerInstance will hold the instance of the Clang compiler for us,
    // managing the various objects needed to run the compiler.
    TheCompInst->createDiagnostics();

    CompilerInvocation::CreateFromArgs(TheCompInst->getInvocation(), args,
                                       TheCompInst->getDiagnostics());
    // need to recreate the diagnostics engine so that it actually listens to warning
    // flags like -Wno-deprecated this cannot go before CreateFromArgs
    TheCompInst->createDiagnostics();
    std::shared_ptr<TargetOptions> to(new TargetOptions(TheCompInst->getTargetOpts()));

    TargetInfo *TI = TargetInfo::CreateTargetInfo(TheCompInst->getDiagnostics(), to);
    TheCompInst->setTarget(TI);

    TheCompInst->createFileManager(FS);
    FileManager &FileMgr = TheCompInst->getFileManager();
    TheCompInst->createSourceManager(FileMgr);
    SourceManager &SourceMgr = TheCompInst->getSourceManager();
    TheCompInst->createPreprocessor(TU_Complete);
    TheCompInst->createASTContext();

    // Set the main file handled by the source manager to the input file.
    SourceMgr.setMainFileID(
            SourceMgr.createFileID(UNIQUEIFY(llvm::MemoryBuffer, membuffer)));
    TheCompInst->getDiagnosticClient().BeginSourceFile(TheCompInst->getLangOpts(),
                                                       &TheCompInst->getPreprocessor());
    Preprocessor &PP = TheCompInst->getPreprocessor();
    PP.getBuiltinInfo().initializeBuiltins(PP.getIdentifierTable(), PP.getLangOpts());
}

static void AddMacro(terra_State *T, Preprocessor &PP, const IdentifierInfo *II,
                     MacroDirective *MD, Obj *table) {
    if (!II->hasMacroDefinition()) return;
    MacroInfo *MI = MD->getMacroInfo();
    if (MI->isFunctionLike()) return;
    bool negate = false;
    const Token *Tok;
    if (MI->getNumTokens() == 2 && MI->getReplacementToken(0).is(clang::tok::minus)) {
        negate = true;
        Tok = &MI->getReplacementToken(1);
    } else if (MI->getNumTokens() == 1) {
        Tok = &MI->getReplacementToken(0);
    } else {
        return;
    }

    if (Tok->isNot(clang::tok::numeric_constant)) return;

    SmallString<64> IntegerBuffer;
    bool NumberInvalid = false;
    StringRef Spelling = PP.getSpelling(*Tok, IntegerBuffer, &NumberInvalid);
    NumericLiteralParser Literal(Spelling, Tok->getLocation(), PP.getSourceManager(),
                                 PP.getLangOpts(), PP.getTargetInfo(),
                                 PP.getDiagnostics());
    if (Literal.hadError) return;
    double V;
    if (Literal.isFloatingLiteral()) {
        llvm::APFloat Result(0.0);
        Literal.GetFloatValue(Result);
        V = Result.convertToDouble();
    } else {
        llvm::APInt Result(64, 0);
        Literal.GetIntegerValue(Result);
        int64_t i = Result.getSExtValue();
        if ((int64_t)(double)i != i)
            return;  // right now we ignore things that are not representable in Lua's
                     // number type eventually we should use LuaJITs ctype support to hold
                     // the larger numbers
        V = i;
    }
    if (negate) V = -V;
    lua_pushnumber(T->L, V);
    table->setfield(II->getName().str().c_str());
}

static void optimizemodule(TerraTarget *TT, llvm::Module *M) {
    // cleanup after clang.
    // in some cases clang will mark stuff AvailableExternally (e.g. atoi on linux)
    // the linker will then delete it because it is not used.
    // switching it to WeakODR means that the linker will keep it even if it is not used
    for (llvm::Module::iterator it = M->begin(), end = M->end(); it != end; ++it) {
        llvm::Function *fn = &*it;
        if (fn->hasAvailableExternallyLinkage() ||
            fn->getLinkage() == llvm::GlobalValue::LinkOnceODRLinkage) {
            fn->setLinkage(llvm::GlobalValue::WeakODRLinkage);
        } else if (fn->getLinkage() == llvm::GlobalValue::LinkOnceAnyLinkage) {
            fn->setLinkage(llvm::GlobalValue::WeakAnyLinkage);
        }
        if (fn->hasDLLImportStorageClass())  // clear dll import linkage because it messes
                                             // up the jit on window
            fn->setDLLStorageClass(llvm::GlobalValue::DefaultStorageClass);
    }

    M->setTargetTriple(
            TT->Triple);  // suppress warning that occur due to unmatched os versions
#if LLVM_VERSION < 170
    PassManager opt;
    llvmutil_addtargetspecificpasses(&opt, TT->tm);
    opt.add(llvm::createFunctionInliningPass());
    llvmutil_addoptimizationpasses(&opt);
    opt.run(*M);
#else
    llvmutil_optimizemodule(M, TT->tm);
#endif
}
static int dofile(terra_State *T, TerraTarget *TT, const char *code,
                  const std::vector<const char *> &args, Obj *result) {
    // CompilerInstance will hold the instance of the Clang compiler for us,
    // managing the various objects needed to run the compiler.
    CompilerInstance TheCompInst;

    llvm::IntrusiveRefCntPtr<llvm::vfs::FileSystem> FS = new LuaOverlayFileSystem(T->L);

    llvm::MemoryBuffer *membuffer =
            llvm::MemoryBuffer::getMemBuffer(code, "<buffer>").release();
    TheCompInst.getHeaderSearchOpts().ResourceDir = "$CLANG_RESOURCE$";
    std::vector<std::string> extra_args;
    InitHeaderSearchFlagsAndArgs(TT->Triple, TheCompInst.getHeaderSearchOpts(),
                                 extra_args);

    // Fold in the extra args first, so that they can be overwritten
    // by the user.
    std::vector<const char *> clang_args;
    for (auto &arg : extra_args) {
        clang_args.push_back(arg.c_str());
    }
    clang_args.insert(clang_args.end(), args.begin(), args.end());
    initializeclang(T, membuffer, clang_args, &TheCompInst, FS);

    CodeGenerator *codegen = CreateLLVMCodeGen(TheCompInst.getDiagnostics(), "mymodule",
#if LLVM_VERSION >= 150
                                               FS,
#endif
                                               TheCompInst.getHeaderSearchOpts(),
                                               TheCompInst.getPreprocessorOpts(),
                                               TheCompInst.getCodeGenOpts(), *TT->ctx);

    std::stringstream ss;
    ss << "__makeeverythinginclanglive_";
    ss << TT->next_unused_id++;
    std::string livenessfunction = ss.str();

    TheCompInst.setASTConsumer(std::unique_ptr<ASTConsumer>(
            new CodeGenProxy(codegen, result, TT, livenessfunction)));

    TheCompInst.createSema(clang::TU_Complete, NULL);

    ParseAST(TheCompInst.getSema(), false, false);

    Obj macros;
    CreateTableWithName(result, "macros", &macros);

    Preprocessor &PP = TheCompInst.getPreprocessor();
    // adjust PP so that it no longer reports errors, which could happen while trying to
    // parse numbers here
    PP.getDiagnostics().setClient(new IgnoringDiagConsumer(), true);

    for (Preprocessor::macro_iterator it = PP.macro_begin(false),
                                      end = PP.macro_end(false);
         it != end; ++it) {
        const IdentifierInfo *II = it->first;
        MacroDirective *MD = it->second.getLatest();
        AddMacro(T, PP, II, MD, &macros);
    }

    llvm::Module *M = codegen->ReleaseModule();
    delete codegen;
    if (!M) {
        terra_reporterror(T, "compilation of included c code failed\n");
    }
    optimizemodule(TT, M);
    if (LLVMLinkModules2(llvm::wrap(TT->external), llvm::wrap(M))) {
        terra_pusherror(T, "linker reported error");
        lua_error(T->L);
    }
    return 0;
}

int include_c(lua_State *L) {
    terra_State *T = terra_getstate(L, 1);
    (void)T;
    lua_getfield(L, TARGET_POS, "llvm_target");
    TerraTarget *TT = (TerraTarget *)terra_tocdatapointer(L, -1);
    const char *code = luaL_checkstring(L, 2);
    int N = lua_objlen(L, 3);
    std::vector<const char *> args;

    args.push_back("-triple");
    args.push_back(TT->Triple.c_str());
    args.push_back("-target-cpu");
    args.push_back(TT->CPU.c_str());
    if (!TT->Features.empty()) {
        args.push_back("-target-feature");
        args.push_back(TT->Features.c_str());
    }

#ifdef _WIN32
    args.push_back("-fms-extensions");
    args.push_back("-fms-volatile");
    args.push_back("-fms-compatibility");
    args.push_back("-fms-compatibility-version=18");
    args.push_back("-Wno-ignored-attributes");
    args.push_back("-flto-visibility-public-std");
    args.push_back("--dependent-lib=msvcrt");
    args.push_back("-fdiagnostics-format");
    args.push_back("msvc");
#endif

    for (int i = 0; i < N; i++) {
        lua_rawgeti(L, 3, i + 1);
        args.push_back(luaL_checkstring(L, -1));
        lua_pop(L, 1);
    }

    lua_newtable(L);  // return a table of loaded functions
    int ref_table = lobj_newreftable(L);
    {
        Obj result;
        lua_pushvalue(L, -2);
        result.initFromStack(L, ref_table);

        dofile(T, TT, code, args, &result);
    }

    lobj_removereftable(L, ref_table);
    return 1;
}

void terra_cwrapperinit(terra_State *T) {
    lua_getfield(T->L, LUA_GLOBALSINDEX, "terra");

    lua_pushlightuserdata(T->L, (void *)T);
    lua_pushcclosure(T->L, include_c, 1);
    lua_setfield(T->L, -2, "registercfile");

    lua_pop(T->L, -1);  // terra object
}
