#include "tcompiler.h"
#include "tkind.h"
#include "terra.h"
extern "C" {
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
}
#include <assert.h>
#include <stdio.h>

#include "tcompilerstate.h" //definition of terra_CompilerState which contains LLVM state
#include "tobj.h"

using namespace llvm;

static int terra_compile(lua_State * L);  //entry point from lua into compiler

void terra_compilerinit(struct terra_State * T) {
    lua_getfield(T->L,LUA_GLOBALSINDEX,"terra");
    lua_pushlightuserdata(T->L,(void*)T);
    lua_pushcclosure(T->L,terra_compile,1);
    lua_setfield(T->L,-2,"compile");
    lua_pop(T->L,1); //remove terra from stack
    T->C = (terra_CompilerState*) malloc(sizeof(terra_CompilerState));
    memset(T->C, 0, sizeof(terra_CompilerState));
    InitializeNativeTarget();
    
    T->C->ctx = &getGlobalContext();
    T->C->m = new Module("terra",*T->C->ctx);
    std::string err;
    T->C->ee = EngineBuilder(T->C->m).setErrorStr(&err).setEngineKind(EngineKind::JIT).create();
    if (!T->C->ee) {
        terra_reporterror(T,"llvm: %s\n",err.c_str());
    }
    T->C->fpm = new FunctionPassManager(T->C->m);
    
    //TODO: add optimization passes here, these are just from llvm tutorial and are probably not good
    T->C->fpm->add(new TargetData(*T->C->ee->getTargetData()));
    // Provide basic AliasAnalysis support for GVN.
    T->C->fpm->add(createBasicAliasAnalysisPass());
    // Promote allocas to registers.
    T->C->fpm->add(createPromoteMemoryToRegisterPass());
    // Also promote aggregates like structs....
    T->C->fpm->add(createScalarReplAggregatesPass());
    // Do simple "peephole" optimizations and bit-twiddling optzns.
    T->C->fpm->add(createInstructionCombiningPass());
    // Reassociate expressions.
    T->C->fpm->add(createReassociatePass());
    // Eliminate Common SubExpressions.
    T->C->fpm->add(createGVNPass());
    // Simplify the control flow graph (deleting unreachable blocks, etc).
    T->C->fpm->add(createCFGSimplificationPass());
    
    T->C->fpm->doInitialization();
}

struct TType { //contains llvm raw type pointer and any metadata about it we need
    Type * type;
    bool issretfunc;
    bool issigned;
    bool islogical;
    bool ispassedaspointer;
};

struct TerraCompiler {
    lua_State * L;
    terra_State * T;
    terra_CompilerState * C;
    IRBuilder<> * B;
    BasicBlock * BB; //current basic block
    Obj funcobj;
    Function * func;
    TType * func_type;
    TType * getType(Obj * typ) {
        TType * t = (TType*) typ->ud("llvm_type");
        if(t == NULL) {
            t = (TType*) lua_newuserdata(T->L,sizeof(TType));
            memset(t,0,sizeof(TType));
            typ->setfield("llvm_type");
            switch(typ->kind("kind")) {
                case T_primitive: {
                    int bytes = typ->number("bytes");
                    switch(typ->kind("type")) {
                        case T_float: {
                            if(bytes == 4) {
                                t->type = Type::getFloatTy(*C->ctx);
                            } else {
                                assert(bytes == 8);
                                t->type = Type::getDoubleTy(*C->ctx);
                            }
                        } break;
                        case T_integer: {
                            t->issigned = typ->boolean("signed");
                            t->type = Type::getIntNTy(*C->ctx,bytes * 8);
                        } break;
                        case T_logical: {
                            t->type = Type::getInt8Ty(*C->ctx);
                            t->islogical = true;
                        } break;
                        default: {
                            printf("kind = %d, %s\n",typ->kind("kind"),tkindtostr(typ->kind("type")));
                            terra_reporterror(T,"type not understood");
                        } break;
                    }
                } break;
                case T_struct: {
                    const char * name = typ->string("name");
                    Obj entries;
                    typ->obj("entries", &entries);
                    int N = entries.size();
                    StructType * st = StructType::create(*C->ctx, name);
                    t->type = st;
                    t->ispassedaspointer = true;
                    std::vector<Type *> entry_types;
                    for(int i = 0; i < N; i++) {
                        Obj v;
                        entries.objAt(i, &v);
                        Obj vt;
                        v.obj("type",&vt);
                        entry_types.push_back(getType(&vt)->type);
                    }
                    st->setBody(entry_types);
                } break;
                case T_pointer: {
                    Obj base;
                    typ->obj("type",&base);
                    t->type = PointerType::getUnqual(getType(&base)->type);
                } break;
                case T_functype: {
                    std::vector<Type*> arguments;
                    Obj params,rets;
                    typ->obj("parameters",&params);
                    typ->obj("returns",&rets);
                    int sz = rets.size();
                    Type * rt; 
                    if(sz == 0) {
                        rt = Type::getVoidTy(*C->ctx);
                    } else {
                        Obj r0;
                        rets.objAt(0,&r0);
                        TType * r0t = getType(&r0);
                        if(sz == 1 && !r0t->ispassedaspointer) {
                            rt = r0t->type;
                        } else {
                            std::vector<Type *> types;
                            for(int i = 0; i < sz; i++) {
                                Obj r;
                                rets.objAt(i,&r);
                                TType * rt = getType(&r);
                                types.push_back(rt->type);
                            }
                            rt = Type::getVoidTy(*C->ctx);
                            Type * st = StructType::get(*C->ctx,types);
                            arguments.push_back(PointerType::getUnqual(st));
                            t->issretfunc = true;
                        }
                    }
                    int psz = params.size();
                    for(int i = 0; i < psz; i++) {
                        Obj p;
                        params.objAt(i,&p);
                        TType * pt = getType(&p);
                        Type * t = pt->type;
                        //TODO: when we construct a function with this type, we need to mark the argument 'byval' so that llvm copies the argument
                        //right now it still works because we make a copy of these arguments anyway
                        //but it may be more efficient to let llvm handle the copy
                        if(pt->ispassedaspointer) {
                            t = PointerType::getUnqual(pt->type);
                        }
                        arguments.push_back(t);
                    }
                    t->type = FunctionType::get(rt,arguments,false); 
                } break;
                case T_array: {
                    Obj base;
                    typ->obj("type",&base);
                    int N = typ->number("N");
                    t->type = ArrayType::get(getType(&base)->type, N);
                    t->ispassedaspointer = true;
                } break;
                default: {
                    printf("kind = %d, %s\n",typ->kind("kind"),tkindtostr(typ->kind("kind")));
                    terra_reporterror(T,"type not understood\n");
                } break;
            }
            assert(t && t->type);
        }
        return t;
    }
    TType * typeOfValue(Obj * v) {
        Obj t;
        v->obj("type",&t);
        return getType(&t);
    }
    GlobalVariable * allocGlobal(Obj * v) {
        const char * name = v->string("name");
        Type * typ = typeOfValue(v)->type;
        GlobalVariable * gv = new GlobalVariable(*C->m, typ, false, GlobalValue::CommonLinkage, UndefValue::get(typ), name);
        lua_pushlightuserdata(L, gv);
        v->setfield("value");
        return gv;
    }
    AllocaInst * allocVar(Obj * v) {
        IRBuilder<> TmpB(&func->getEntryBlock(),
                          func->getEntryBlock().begin()); //make sure alloca are at the beginning of the function
                                                          //TODO: is this really needed? this is what llvm example code does...
        AllocaInst * a = TmpB.CreateAlloca(typeOfValue(v)->type,0,v->string("name"));
        lua_pushlightuserdata(L,a);
        v->setfield("value");
        return a;
    }

    void getOrCreateFunction(Obj * funcobj, Function ** rfn, TType ** rtyp) {
        Function * fn = (Function *) funcobj->ud("llvm_function");
        Obj ftype;
        funcobj->obj("type",&ftype);
        *rtyp = getType(&ftype);
        if(!fn) {
            const char * name = funcobj->string("name");
            fn = Function::Create(cast<FunctionType>((*rtyp)->type), Function::ExternalLinkage,name, C->m);
            if ((*rtyp)->issretfunc) {
                fn->arg_begin()->addAttr(Attribute::StructRet | Attribute::NoAlias);
            } 
            lua_pushlightuserdata(L,fn);
            funcobj->setfield("llvm_function");
        }
        *rfn = fn;
    }
    void run(terra_State * _T, int ref_table) {
        T = _T;
        L = T->L;
        C = T->C;
        B = new IRBuilder<>(*C->ctx);
        
        lua_pushvalue(T->L,-2); //the original argument
        funcobj.initFromStack(T->L, ref_table);
        
        
        getOrCreateFunction(&funcobj,&func,&func_type);
        
        BB = BasicBlock::Create(*C->ctx,"entry",func);
        
        B->SetInsertPoint(BB);
        
        Obj typedtree;
        Obj parameters;
        
        funcobj.obj("typedtree",&typedtree);
        typedtree.obj("parameters",&parameters);
        int nP = parameters.size();
        Function::arg_iterator ai = func->arg_begin();
        if(func_type->issretfunc)
            ++ai; //first argument is the return structure, skip it when loading arguments
        for(int i = 0; i < nP; i++) {
            Obj p;
            parameters.objAt(i,&p);
            TType * t = typeOfValue(&p);
            if(t->ispassedaspointer) { //this is already a copy, so we can assign the variable directly to its memory
                Value * v = ai;
                lua_pushlightuserdata(L,v);
                p.setfield("value");
            } else {
                AllocaInst * a = allocVar(&p);
                B->CreateStore(ai,a);
            }
            ++ai;
        }
        
        Obj body;
        typedtree.obj("body",&body);
        emitStmt(&body);
        if(BB) { //no terminating return statment, we need to insert one
            emitReturnUndef();
        }
        
        C->m->dump();
        verifyFunction(*func);
        C->fpm->run(*func);
        C->m->dump();
        
        void * ptr = C->ee->getPointerToFunction(func);
        
        void ** data = (void**) lua_newuserdata(L,sizeof(void*));
        assert(ptr);
        *data = ptr;
        funcobj.setfield("fptr");
        
        //cleanup -- ensure we left the stack the way we started
        assert(lua_gettop(T->L) == ref_table);
        delete B;
    }
    
    Value * emitUnary(Obj * exp, Obj * ao) {
        TType * t = typeOfValue(exp);
        Value * a = emitExp(ao);
        switch(exp->kind("operator")) {
            case T_not:
                return B->CreateNot(a);
                break;
            case T_minus:
                if(t->type->isIntegerTy()) {
                    return B->CreateNeg(a);
                } else {
                    return B->CreateFNeg(a);
                }
                break;
            case T_addressof: /*fallthrough*/
            case T_dereference:
                //addressof and dereference are no-ops since 
                //typechecking inserted l-to-r values for when
                //where the pointers need to be dereferenced
                return a;
                break;
            default:
                assert(!"NYI - unary");
                break;
        }
    }
    Value * emitCompare(Obj * exp, Obj * ao, Value * a, Value * b) {
        TType * t = typeOfValue(ao);
#define RETURN_OP(op) \
if(t->type->isIntegerTy()) { \
    return B->CreateICmp(CmpInst::ICMP_##op,a,b); \
} else { \
    return B->CreateFCmp(CmpInst::FCMP_O##op,a,b); \
}
#define RETURN_SOP(op) \
if(t->type->isIntegerTy()) { \
    if(t->issigned) { \
        return B->CreateICmp(CmpInst::ICMP_S##op,a,b); \
    } else { \
        return B->CreateICmp(CmpInst::ICMP_U##op,a,b); \
    } \
} else { \
    return B->CreateFCmp(CmpInst::FCMP_O##op,a,b); \
}
        
        switch(exp->kind("operator")) {
            case T_ne: RETURN_OP(NE) break;
            case T_eq: RETURN_OP(EQ) break;
            case T_lt: RETURN_SOP(LT) break;
            case T_gt: RETURN_SOP(GT) break;
            case T_ge: RETURN_SOP(GE) break;
            case T_le: RETURN_SOP(LE) break;
            default: 
                assert(!"unknown op");
                return NULL;
                break;
        }
#undef RETURN_OP
#undef RETURN_SOP
    }
    
    Value * emitLazyLogical(TType * t, Obj * ao, Obj * bo, bool isAnd) {
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
        Value * result = B->CreateAlloca(t->type);
        Value * a = emitExp(ao);
        Value * acond = emitCond(a);
        BasicBlock * stmtB = createAndInsertBB("logicalcont");
        BasicBlock * emptyB = createAndInsertBB("logicalnop");
        BasicBlock * mergeB = createAndInsertBB("merge");
        B->CreateCondBr(acond, (isAnd) ? stmtB : emptyB, (isAnd) ? emptyB : stmtB);
        setInsertBlock(stmtB);
        Value * b = emitExp(bo);
        B->CreateStore(b, result);
        B->CreateBr(mergeB);
        setInsertBlock(emptyB);
        B->CreateStore(a, result);
        B->CreateBr(mergeB);
        setInsertBlock(mergeB);
        return B->CreateLoad(result, "logicalop");
    }
    
    Value * emitPointerArith(T_Kind kind, Value * pointer, Value * number){
        if(kind == T_add) {
            return B->CreateGEP(pointer,number);
        } else if(kind == T_sub) {
            Value * numNeg = B->CreateNeg(number);
            return B->CreateGEP(pointer,numNeg);
        } else {
            assert(!"unexpected pointer arith");
            return NULL;
        }
    }
    Value * emitPointerSub(TType * t, Value * a, Value * b) {
        return B->CreatePtrDiff(a, b);
    }
    Value * emitBinary(Obj * exp, Obj * ao, Obj * bo) {
        TType * t = typeOfValue(exp);
        T_Kind kind = exp->kind("operator");

        //check for lazy operators before evaluateing arguments
        if(t->islogical) {
            switch(kind) {
                case T_and:
                    return emitLazyLogical(t,ao,bo,true);
                case T_or:
                    return emitLazyLogical(t,ao,bo,false);
                default:
                    break;
            }
        }
        
        //ok, we have eager operators, lets evalute the arguments then emit
        Value * a = emitExp(ao);
        Value * b = emitExp(bo);

        TType * at = typeOfValue(ao);
        TType * bt = typeOfValue(bo);
        
        //check for pointer arithmetic first pointer arithmetic first
        if(at->type->isPointerTy()) {
            assert(kind == T_add || kind == T_sub);
            if(bt->type->isPointerTy()) {
                return emitPointerSub(t,a,b);
            } else {
                assert(bt->type->isIntegerTy());
                return emitPointerArith(kind, a, b);
            }
        }

#define RETURN_OP(op) \
if(t->type->isIntegerTy()) { \
    return B->Create##op(a,b); \
} else { \
    return B->CreateF##op(a,b); \
}
#define RETURN_SOP(op) \
if(t->type->isIntegerTy()) { \
    if(t->issigned) { \
        return B->CreateS##op(a,b); \
    } else { \
        return B->CreateU##op(a,b); \
    } \
} else { \
    return B->CreateF##op(a,b); \
}
        switch(kind) {
            case T_add: RETURN_OP(Add) break;
            case T_sub: RETURN_OP(Sub) break;
            case T_mul: RETURN_OP(Mul) break;
            case T_div: RETURN_SOP(Div) break;
            case T_mod: RETURN_SOP(Rem) break;
            case T_pow: return B->CreateXor(a, b);
            case T_and: return B->CreateAnd(a,b);
            case T_or: return B->CreateOr(a,b);
            case T_ne: case T_eq: case T_lt: case T_gt: case T_ge: case T_le: {
                Value * v = emitCompare(exp,ao,a,b);
                return B->CreateZExt(v, t->type);
            } break;
            default:
                assert(!"NYI - binary");
                break;
        }
#undef RETURN_OP
#undef RETURN_SOP
    }
    Value * emitStructCast(Obj * exp, TType * from, TType * to, Value * input) {
        //allocate memory to hold input variable
        Obj structvariable;
        exp->obj("structvariable", &structvariable);
        Value * sv = allocVar(&structvariable);
        B->CreateStore(input,sv);
        
        //allocate temporary to hold output variable
        Value * output = B->CreateAlloca(to->type);
        
        Obj entries;
        exp->obj("entries",&entries);
        int N = entries.size();
        
        for(int i = 0; i < N; i++) {
            Obj entry;
            entries.objAt(i,&entry);
            Obj value;
            entry.obj("value", &value);
            int idx = entry.number("index");
            int64_t idxs[] = {0, idx };
            Value * oe = emitCGEP(output,idxs,2);
            Value * in = emitExp(&value); //these expressions will select from the structvariable and perform any casts necessary
            B->CreateStore(in,oe);
        }
        return B->CreateLoad(output);
    }
    Value * emitArrayToPointer(TType * from, TType * to, Value * exp) {
        //typechecker ensures that input to array to pointer is an lvalue
        int64_t idxs[] = {0,0};
        return emitCGEP(exp,idxs,2);
    }
    Value * emitPrimitiveCast(TType * from, TType * to, Value * exp) {
        int fsize = from->type->getPrimitiveSizeInBits();
        int tsize = to->type->getPrimitiveSizeInBits(); 
        if(from->type->isIntegerTy()) {
            if(to->type->isIntegerTy()) {
                if(fsize > tsize) {
                    return B->CreateTrunc(exp, to->type);
                } else if(fsize == tsize) {
                    return exp; //no-op in llvm since its types are not signed
                } else {
                    if(from->issigned) {
                        return B->CreateSExt(exp, to->type);
                    } else {
                        return B->CreateZExt(exp, to->type);
                    }
                }
            } else if(to->type->isFloatingPointTy()) {
                if(from->issigned) {
                    return B->CreateSIToFP(exp, to->type);
                } else {
                    return B->CreateUIToFP(exp, to->type);
                }
            } else goto nyi;
        } else if(from->type->isFloatingPointTy()) {
            if(to->type->isIntegerTy()) {
                if(to->issigned) {
                    return B->CreateFPToSI(exp, to->type);
                } else {
                    return B->CreateFPToUI(exp, to->type);
                }
            } else if(to->type->isFloatingPointTy()) {
                if(fsize < tsize) {
                    return B->CreateFPExt(exp, to->type);
                } else {
                    return B->CreateFPTrunc(exp, to->type);
                }
            } else goto nyi;
        } else goto nyi;
    nyi:
        assert(!"NYI - casts");
        return NULL;
        
    }
    Value * emitExp(Obj * exp) {
        switch(exp->kind("kind")) {
            case T_var:  {
                Obj def;
                exp->obj("definition",&def);
                Value * v = (Value*) def.ud("value");
                assert(v);
                return v;
            } break;
            case T_ltor: {
                Obj e;
                exp->obj("expression",&e);
                Value * v = emitExp(&e);
                return B->CreateLoad(v);
            } break;
            case T_rtol: {
                Obj e;
                exp->obj("expression",&e);
                Value * v = emitExp(&e);
                Value * r = B->CreateAlloca(v->getType());
                B->CreateStore(v, r);
                return r;
            } break;
            case T_operator: {
                
                Obj exps;
                exp->obj("operands",&exps);
                int N = exps.size();
                if(N == 1) {
                    Obj a;
                    exps.objAt(0,&a);
                    return emitUnary(exp,&a);
                } else if(N == 2) {
                    Obj a,b;
                    exps.objAt(0,&a);
                    exps.objAt(1,&b);
                    return emitBinary(exp,&a,&b);
                } else {
                    assert(!"NYI - greater than 2 operands?");
                    return NULL;
                }
                switch(exp->kind("operator")) {
                    case T_add: {
                        TType * t = typeOfValue(exp);
                        Obj exps;
                        
                        if(t->type->isFPOrFPVectorTy()) {
                            Obj a,b;
                            exps.objAt(0,&a);
                            exps.objAt(1,&b);
                            return B->CreateFAdd(emitExp(&a),emitExp(&b));
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
                exp->obj("value",&value);
                exp->obj("index",&idx);
                
                Value * valueExp = emitExp(&value);
                Value * idxExp = emitExp(&idx);
                bool pa = exp->boolean("lvalue");
                
                //if the array is an rvalue type, we need to store it, then index it, and then reload it
                //otherwise, if we have an  lvalue, we just calculate the offset
                if(!pa) {
                   Value * mem = B->CreateAlloca(valueExp->getType());
                    B->CreateStore(valueExp, mem);
                    valueExp = mem;
                }
                
                std::vector<Value*> idxs;
                
                if(!typeOfValue(&value)->type->isPointerTy()) {
                    idxs.push_back(ConstantInt::get(Type::getInt32Ty(*C->ctx),0));
                } //raw pointer types use the first GEP index, while arrays first do {0,idx}
                idxs.push_back(idxExp);
                
                Value * result = B->CreateGEP(valueExp, idxs);
                
                if(!pa) {
                    result = B->CreateLoad(result);
                }
                
                return result;
            } break;
            case T_literal: {
                TType * t = typeOfValue(exp);
                
                if(t->islogical) {
                   bool b = exp->boolean("value"); 
                   return ConstantInt::get(t->type,b);
                } else if(t->type->isIntegerTy()) {
                    uint64_t integer = exp->integer("value");
                    return ConstantInt::get(t->type, integer);
                } else if(t->type->isFloatingPointTy()) {
                    double dbl = exp->number("value");
                    return ConstantFP::get(t->type, dbl);
                } else if(t->type->isPointerTy()) {
                    PointerType * pt = (PointerType*) t->type;
                    if(pt->getElementType()->isFunctionTy()) {
                        Obj func;
                        exp->obj("value",&func);
                        TType * ftyp;
                        Function * fn;
                        getOrCreateFunction(&func,&fn,&ftyp);
                        return fn;
                    } else {
                        assert(!"NYI - pointer literal");
                    }
                } else {
                    exp->dump();
                    assert(!"NYI - literal");
                }
            } break;
            case T_cast: {
                Obj a;
                Obj to,from;
                exp->obj("expression",&a);
                exp->obj("to",&to);
                exp->obj("from",&from);
                TType * fromT = getType(&from);
                TType * toT = getType(&to);
                Value * v = emitExp(&a);
                if(fromT->type->isStructTy()) {
                    return emitStructCast(exp,fromT,toT,v);
                } else if(fromT->type->isArrayTy()) {
                    return emitArrayToPointer(fromT,toT,v);
                } else if(fromT->type->isPointerTy()) {
                    if(toT->type->isPointerTy()) {
                        return B->CreateBitCast(v, toT->type);
                    } else {
                        assert(toT->type->isIntegerTy());
                        return B->CreatePtrToInt(v, toT->type);
                    }
                } else if(toT->type->isPointerTy()) {
                    assert(fromT->type->isIntegerTy());
                    return B->CreateIntToPtr(v, toT->type);
                } else {
                    return emitPrimitiveCast(fromT,toT,v);
                }
            } break;
            case T_apply: {
                Value * v = emitCall(exp,true);
                return v;
            } break;   
            case T_extractreturn: {
                Obj index,resulttable,value;
                int idx = exp->number("index");
                exp->obj("result",&resulttable);
                Value * v = (Value *) resulttable.ud("struct");
                assert(v);
                //v->dump();
                int64_t idxs[] = {0,idx};
                Value * addr = emitCGEP(v,idxs,2);
                return B->CreateLoad(addr);
            } break;
            case T_select: {
                Obj obj;
                exp->obj("value",&obj);
                Value * v = emitExp(&obj);
                int offset = exp->number("index");
                if(exp->boolean("lvalue")) {
                    int64_t idxs[] = {0, offset};
                    return emitCGEP(v,idxs,2);
                } else {
                    return B->CreateExtractValue(v, offset);
                }
            } break;
            case T_identity: {
                Obj value;
                exp->obj("value",&value);
                return emitExp(&value);
            } break;
            case T_constructor: {
                Obj records;
                exp->obj("records",&records);
                Value * result = B->CreateAlloca(typeOfValue(exp)->type);
                std::vector<Value *> values;
                emitParameterList(&records,&values,NULL);
                for(size_t i = 0; i < values.size(); i++) {
                    int64_t idxs[] = { 0, i };
                    Value * addr = emitCGEP(result,idxs,2);
                    B->CreateStore(values[i],addr);
                }
                return B->CreateLoad(result);
            } break;
            default: {
                assert(!"NYI - exp");
            } break;
        }
    }
    BasicBlock * createBB(const char * name) {
        BasicBlock * bb = BasicBlock::Create(*C->ctx, name);
        return bb;
    }
    BasicBlock * createAndInsertBB(const char * name) {
        BasicBlock * bb = createBB(name);
        insertBB(bb);
        return bb;
    }
    void insertBB(BasicBlock * bb) {
        func->getBasicBlockList().push_back(bb);
    }
    Value * emitCond(Obj * cond) {
        return emitCond(emitExp(cond));
    }
    Value * emitCond(Value * cond) {
        return B->CreateTrunc(cond, Type::getInt1Ty(*C->ctx));
    }
    void emitIfBranch(Obj * ifbranch, BasicBlock * footer) {
        Obj cond,body;
        ifbranch->obj("condition", &cond);
        ifbranch->obj("body",&body);
        Value * v = emitCond(&cond);
        BasicBlock * thenBB = createAndInsertBB("then");
        BasicBlock * continueif = createBB("else");
        B->CreateCondBr(v, thenBB, continueif);
        
        setInsertBlock(thenBB);
        
        emitStmt(&body);
        if(BB)
            B->CreateBr(footer);
        insertBB(continueif);
        setInsertBlock(continueif);
        
    }
    
    void setInsertBlock(BasicBlock * bb) {
        BB = bb;
        B->SetInsertPoint(BB);
    }
    void setBreaktable(Obj * loop, BasicBlock * exit) {
        //set the break table for this loop to point to the loop exit
        Obj breaktable;
        loop->obj("breaktable",&breaktable);
        
        lua_pushlightuserdata(L, exit);
        breaktable.setfield("value");
    }
    BasicBlock * getOrCreateBlockForLabel(Obj * lbl) {
        BasicBlock * bb = (BasicBlock *) lbl->ud("basicblock");
        if(!bb) {
            bb = createBB(lbl->string("value"));
            lua_pushlightuserdata(L,bb);
            lbl->setfield("basicblock");
        }
        return bb;
    }
    Value * emitCGEP(Value * st, int64_t * idxs, size_t N) {
        std::vector<Value *> ivalues;
        for(size_t i = 0; i < N; i++) {
            ivalues.push_back(ConstantInt::get(Type::getInt32Ty(*C->ctx),idxs[i]));
        }
        return B->CreateGEP(st, ivalues);
    }
    Value * emitCall(Obj * call, bool truncateto1arg) {
        Obj paramlist;
        Obj returns;
        Obj func;
        call->obj("arguments",&paramlist);
        call->obj("types",&returns);
        call->obj("value",&func);
        
        Value * fn = emitExp(&func);
        
        Obj fnptrtyp;
        func.obj("type",&fnptrtyp);
        Obj fntypobj;
        fnptrtyp.obj("type",&fntypobj);
        TType * ftyp = getType(&fntypobj);
        
        
        std::vector<Value *> params;
        std::vector<TType *> types;
        int returnsN = returns.size();
        
        Value * sret = NULL;
        if(ftyp->issretfunc) {
            //create struct to hold the list
            FunctionType * castft = (FunctionType*) ftyp->type;
            PointerType * pt = cast<PointerType>(castft->getParamType(0));
            sret = B->CreateAlloca(pt->getElementType());
            params.push_back(sret);
            types.push_back(NULL);
        }
        
        int first_arg = params.size();
        emitParameterList(&paramlist,&params,&types);
        for(int i = first_arg; i < params.size(); i++) {
            if(types[i]->ispassedaspointer) {
                Value * p = B->CreateAlloca(types[i]->type);
                B->CreateStore(params[i],p);
                params[i] = p;
            }
        }
        
        Value * result = B->CreateCall(fn, params);
        
        if(returnsN == 0) {
            return NULL;
        } else if(returnsN == 1 && !ftyp->issretfunc) {
            assert(truncateto1arg); //single return functions should not appear as multi-return calls
            return result;
        } else {
            if(truncateto1arg) {
                int64_t idx[] = {0,0};
                Value * addr = emitCGEP(sret,idx,2);
                return B->CreateLoad(addr, "ret");
            } else {
                return sret; //return the pointer to the struct itself so that it can be linked to the extract expressions
            }
        }
    }
    void emitReturnUndef() {
        Type * rt = func->getReturnType();
        if(rt->isVoidTy()) {
            B->CreateRetVoid();
        } else {
            B->CreateRet(UndefValue::get(rt));
        }
    }
    void emitMultiReturnCall(Obj * call) {
        Value * rvalues = emitCall(call,false);
        Obj result;
        call->obj("result",&result);
        lua_pushlightuserdata(L, rvalues);
        result.setfield("struct");
    }
    void emitParameterList(Obj * paramlist, std::vector<Value*> * results, std::vector<TType*> * types) {
        
        Obj params;
        
        paramlist->obj("parameters",&params);
        
        int minN = paramlist->number("minsize");
        int sizeN = paramlist->number("size");
        if(minN != 0) {
            //emit arguments before possible function call
            for(int i = 0; i < minN - 1; i++) {
                Obj v;
                params.objAt(i,&v);
                results->push_back(emitExp(&v));
                if(types)
                    types->push_back(typeOfValue(&v));
            }
            Obj call;
            //if there is a function call, emit it now
            if(paramlist->obj("call",&call)) {
                emitMultiReturnCall(&call);
            }
            //emit last argument, or (if there was a call) the list of extractors from the function call
            for(int i = minN - 1; i < sizeN; i++) {
                Obj v;
                params.objAt(i,&v);
                results->push_back(emitExp(&v));
                if(types)
                    types->push_back(typeOfValue(&v));
            }
        }
        
    }
    void emitStmt(Obj * stmt) {     
        T_Kind kind = stmt->kind("kind");
        if(!BB) { //dead code, no emitting
            if(kind == T_label) { //unless there is a label, then someone can jump here
                BasicBlock * bb = getOrCreateBlockForLabel(stmt);
                insertBB(bb);
                setInsertBlock(bb);
            }
            return;
        }
        switch(kind) {
            case T_block: {
                Obj stmts;
                stmt->obj("statements",&stmts);
                int N = stmts.size();
                for(int i = 0; i < N; i++) {
                    Obj s;
                    stmts.objAt(i,&s);
                    emitStmt(&s);
                }
            } break;
            case T_return: {
                Obj exps;
                stmt->obj("expressions",&exps);
                
                std::vector<Value *> results;
                emitParameterList(&exps, &results,NULL);
                
                if(results.size() == 0) {
                    B->CreateRetVoid();
                } else if (results.size() == 1 && !this->func_type->issretfunc) {
                    B->CreateRet(results[0]);
                } else {
                    //multiple return values, look up the sret pointer
                    Value * st = func->arg_begin();
                    
                    for(int i = 0; i < results.size(); i++) {
                        int64_t idx[] = {0,i};
                        Value * addr = emitCGEP(st,idx,2);
                        B->CreateStore(results[i], addr);
                    }
                    B->CreateRetVoid();
                }
                BB = NULL;
            } break;
            case T_label: {
                BasicBlock * bb = getOrCreateBlockForLabel(stmt);
                B->CreateBr(bb);
                insertBB(bb);
                setInsertBlock(bb);
            } break;
            case T_goto: {
                Obj lbl;
                stmt->obj("definition",&lbl);
                BasicBlock * bb = getOrCreateBlockForLabel(&lbl);
                B->CreateBr(bb);
                BB = NULL;
            } break;
            case T_break: {
                Obj def;
                stmt->obj("breaktable",&def);
                BasicBlock * breakpoint = (BasicBlock *) def.ud("value");
                assert(breakpoint);
                B->CreateBr(breakpoint);
                BB = NULL;
            } break;
            case T_while: {
                Obj cond,body;
                stmt->obj("condition",&cond);
                stmt->obj("body",&body);
                BasicBlock * condBB = createAndInsertBB("condition");
                
                B->CreateBr(condBB);
                
                setInsertBlock(condBB);
                
                Value * v = emitCond(&cond);
                BasicBlock * loopBody = createAndInsertBB("whilebody");
    
                BasicBlock * merge = createBB("merge");
                
                setBreaktable(stmt,merge);
                
                B->CreateCondBr(v, loopBody, merge);
                
                setInsertBlock(loopBody);
                
                emitStmt(&body);
                
                if(BB)
                    B->CreateBr(condBB);
                
                insertBB(merge);
                setInsertBlock(merge);
            } break;
            case T_if: {
                Obj branches;
                stmt->obj("branches",&branches);
                int N = branches.size();
                BasicBlock * footer = createBB("merge");
                for(int i = 0; i < N; i++) {
                    Obj branch;
                    branches.objAt(i,&branch);
                    emitIfBranch(&branch,footer);
                }
                Obj orelse;
                stmt->obj("orelse",&orelse);
                emitStmt(&orelse);
                if(BB)
                    B->CreateBr(footer);
                insertBB(footer);
                setInsertBlock(footer);
            } break;
            case T_repeat: {
                Obj cond,body;
                stmt->obj("condition",&cond);
                stmt->obj("body",&body);
                
                BasicBlock * loopBody = createAndInsertBB("repeatbody");
                BasicBlock * merge = createBB("merge");
                
                setBreaktable(stmt,merge);
                
                B->CreateBr(loopBody);
                setInsertBlock(loopBody);
                emitStmt(&body);
                if(BB) {
                    Value * c = emitCond(&cond);
                    B->CreateCondBr(c, merge, loopBody);
                }
                insertBB(merge);
                setInsertBlock(merge);
                
            } break;
            case T_defvar: {
                std::vector<Value *> rhs;
                
                Obj inits;
                bool has_inits = stmt->obj("initializers",&inits);
                if(has_inits)
                    emitParameterList(&inits, &rhs,NULL);
                
                Obj vars;
                stmt->obj("variables",&vars);
                int N = vars.size();
                bool isglobal = stmt->boolean("isglobal");
                for(int i = 0; i < N; i++) {
                    Obj v;
                    vars.objAt(i,&v);
                    Value * addr;
                    
                    if(isglobal) {
                        addr = allocGlobal(&v);
                    } else {
                        addr = allocVar(&v);
                    }
                    if(has_inits)
                        B->CreateStore(rhs[i],addr);
                }
            } break;
            case T_assignment: {
                std::vector<Value *> rhsexps;
                Obj rhss;
                stmt->obj("rhs",&rhss);
                emitParameterList(&rhss,&rhsexps,NULL);
                Obj lhss;
                stmt->obj("lhs",&lhss);
                int N = lhss.size();
                for(int i = 0; i < N; i++) {
                    Obj lhs;
                    lhss.objAt(i,&lhs);
                    Value * lhsexp = emitExp(&lhs);
                    B->CreateStore(rhsexps[i],lhsexp);
                }
            } break;
            default: {
                emitExp(stmt);
            } break;
        }
    }
};

static int terra_compile(lua_State * L) { //entry point into compiler from lua code
    terra_State * T = (terra_State*) lua_topointer(L,lua_upvalueindex(1));
    assert(T->L == L);
    
    //create lua table to hold object references anchored on stack
    int ref_table = lobj_newreftable(T->L);
    
    {
        TerraCompiler c;
        c.run(T,ref_table);
    } //scope to ensure that all Obj held in the compiler are destroyed before we pop the reference table off the stack
    
    lobj_removereftable(T->L,ref_table);
    
    return 0;
}
