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

#include "llvm/DerivedTypes.h"
#include "llvm/ExecutionEngine/ExecutionEngine.h"
#include "llvm/ExecutionEngine/JIT.h"
#include "llvm/LLVMContext.h"
#include "llvm/Module.h"
#include "llvm/PassManager.h"
#include "llvm/Analysis/Verifier.h"
#include "llvm/Analysis/Passes.h"
#include "llvm/Target/TargetData.h"
#include "llvm/Transforms/Scalar.h"
#include "llvm/Support/IRBuilder.h"
#include "llvm/Support/TargetSelect.h"
using namespace llvm;

struct terra_CompilerState {
	Module * m;
	LLVMContext * ctx;
	ExecutionEngine * ee;
	FunctionPassManager * fpm;
};

static int terra_compile(lua_State * L);  //entry point from lua into compiler

void terra_compilerinit(struct terra_State * T) {
	lua_getfield(T->L,LUA_GLOBALSINDEX,"terra");
	lua_pushlightuserdata(T->L,(void*)T);
	lua_pushcclosure(T->L,terra_compile,1);
	lua_setfield(T->L,-2,"compile");
	lua_pop(T->L,1); //remove terra from stack
	T->C = (terra_CompilerState*) malloc(sizeof(terra_CompilerState));
	InitializeNativeTarget();
	
	T->C->ctx = &getGlobalContext();
	T->C->m = new Module("terra",*T->C->ctx);
	std::string err;
	T->C->ee = EngineBuilder(T->C->m).setErrorStr(&err).create();
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
//object to hold reference to lua object and help extract information
struct Obj {
	Obj() {
		ref = LUA_NOREF; L = NULL;
	}
	void initFromStack(lua_State * L, int ref_table) {
		freeref();
		this->L = L;
		this->ref_table = ref_table;
		assert(!lua_isnil(this->L,-1));
		this->ref = luaL_ref(this->L,this->ref_table);
	}
	~Obj() {
		freeref();
	}
	int size() {
		push();
		int i = lua_objlen(L,-1);
		pop();
		return i;
	}
	void objAt(int i, Obj * r) {
		push();
		lua_rawgeti(L,-1,i+1); //stick to 0-based indexing in C code...
		r->initFromStack(L,ref_table);
		pop();
	}
	double number(const char * field) {
		push();
		lua_getfield(L,-1,field);
		double r = lua_tonumber(L,-1);
		pop(2);
		return r;
	}
	uint64_t integer(const char * field) {
		push();
		lua_getfield(L,-1,field);
		const void * ud = lua_touserdata(L,-1);
		pop(2);
		uint64_t i = *(const uint64_t*)ud;
		return i;
	}
    bool boolean(const char * field) {
        push();
        lua_getfield(L,-1,field);
        bool v = lua_toboolean(L,-1);
        pop(2);
        return v;
    }
	const char * string(const char * field) {
		push();
		lua_getfield(L,-1,field);
		const char * r = luaL_checkstring(L,-1);
		pop(2);
		return r;
	}
	bool obj(const char * field, Obj * r) {
		push();
		lua_getfield(L,-1,field);
		if(lua_isnil(L,-1)) {
			pop(2);
			return false;
		} else {
			r->initFromStack(L,ref_table);
			pop();
			return true;
		}
	}
	void * ud(const char * field) {
		push();
		lua_getfield(L,-1,field);
		void * u = lua_touserdata(L,-1);
		pop(2);
		return u;
	}
	void pushfield(const char * field) {
		push();
		lua_getfield(L,-1,field);
		lua_remove(L,-2);
	}
	void push() {
		//fprintf(stderr,"getting %d %d\n",ref_table,ref);
		assert(lua_gettop(L) >= ref_table);
		lua_rawgeti(L,ref_table,ref);
	}
	T_Kind kind(const char * field) {
		push();
		lua_getfield(L,-1,field);
		int k = luaL_checkint(L,-1);
		pop(2);
		return (T_Kind) k;
	}
	void setfield(const char * key) { //sets field to value on top of the stack and pops it off
		assert(!lua_isnil(L,-1));
        push();
		lua_pushvalue(L,-2);
		lua_setfield(L,-2,key);
		pop(2);
	}
	void dump() {
        printf("object is:\n");
        
        lua_getfield(L,LUA_GLOBALSINDEX,"terra");
        lua_getfield(L,-1,"tree");
        
        lua_getfield(L,-1,"printraw");
        push();
        lua_call(L, 1, 0);
        
        lua_pop(L,2);
        
        printf("stack is:\n");
		int n = lua_gettop(L);
		for (int i = 1; i <= n; i++) {
			printf("%d: (%s) %s\n",i,lua_typename(L,lua_type(L,i)),lua_tostring(L, i));
		}
	}
private:
	void freeref() {
		if(ref != LUA_NOREF) {
			luaL_unref(L,ref_table,ref);
			L = NULL;
			ref = LUA_NOREF;
		}
	}
	void pop(int n = 1) {
		lua_pop(L,n);
	}
	int ref;
	int ref_table;
	lua_State * L; 
};

static void terra_compile_llvm(terra_State * T) {
	Obj func;

}

struct TType { //contains llvm raw type pointer and any metadata about it we need
	Type * type;
	bool issigned;
	bool islogical;
};

struct TerraCompiler {
	lua_State * L;
	terra_State * T;
	terra_CompilerState * C;
	IRBuilder<> * B;
	BasicBlock * BB; //current basic block
	Obj funcobj;
	Function * func;
	TType * getType(Obj * typ) {
		TType * t = (TType*) typ->ud("llvm_type");
		if(t == NULL) {
			t = (TType*) lua_newuserdata(T->L,sizeof(TType));
			memset(t,0,sizeof(TType));
			typ->setfield("llvm_type");
			switch(typ->kind("kind")) {
				case T_builtin: {
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
					} else if(sz == 1) {
						Obj r0;
						rets.objAt(0,&r0);
						TType * r0t = getType(&r0);
						rt = r0t->type;
					} else {
						terra_reporterror(T,"NYI - multiple returns\n");
					}
					int psz = params.size();
					for(int i = 0; i < psz; i++) {
						Obj p;
						params.objAt(i,&p);
						TType * pt = getType(&p);
						arguments.push_back(pt->type);
					}
					t->type = FunctionType::get(rt,arguments,false); 
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
	AllocaInst * allocVar(Obj * v) {
		IRBuilder<> TmpB(&func->getEntryBlock(),
                          func->getEntryBlock().begin()); //make sure alloca are at the beginning of the function
                                                          //TODO: is this really needed? this is what llvm example code does...
		AllocaInst * a = TmpB.CreateAlloca(typeOfValue(v)->type,0,v->string("name"));
		lua_pushlightuserdata(L,a);
		v->setfield("value");
		return a;
	}
    int numReturnValues() {
        Obj typedtree;
        funcobj.obj("typedtree",&typedtree);
        Obj typ;
        typedtree.obj("type",&typ);
        Obj returns;
        typ.obj("returns",&returns);
        return returns.size();
    }
	void run(terra_State * _T) {
		T = _T;
		L = T->L;
		C = T->C;
		B = new IRBuilder<>(*C->ctx);
		//create lua table to hold object references anchored on stack
		lua_newtable(T->L);
		int ref_table = lua_gettop(T->L);
		lua_pushvalue(T->L,-2); //the original argument
		funcobj.initFromStack(T->L, ref_table);
		
		Obj typedtree;
		funcobj.obj("typedtree",&typedtree);
		Obj ftype;
		typedtree.obj("type",&ftype);
		TType * func_type = getType(&ftype);
		const char * name = funcobj.string("name");
		func = Function::Create(cast<FunctionType>(func_type->type), Function::ExternalLinkage,name, C->m);
		BB = BasicBlock::Create(*C->ctx,"entry",func);
		B->SetInsertPoint(BB);
		
		Obj parameters;
		typedtree.obj("parameters",&parameters);
		int nP = parameters.size();
		Function::arg_iterator ai = func->arg_begin();
		for(int i = 0; i < nP; i++) {
			Obj p;
			parameters.objAt(i,&p);
			AllocaInst * a = allocVar(&p);
			B->CreateStore(ai,a);
			++ai;
		}
		
		Obj body;
		typedtree.obj("body",&body);
		emitStmt(&body);
        if(BB) { //no terminating return statment, we need to insert one
            if(numReturnValues() == 0) {
                B->CreateRetVoid();
            } else {
                FunctionType * ftype = cast<FunctionType>(func_type->type);
                B->CreateRet(UndefValue::get(ftype->getReturnType()));
            }
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
    Value * emitCast(TType * from, TType * to, Value * exp) {
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
                        B->CreateSExt(exp, to->type);
                    } else {
                        B->CreateZExt(exp, to->type);
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
            case T_literal: {
                TType * t = typeOfValue(exp);
                
                if(t->islogical) {
                   bool b = exp->boolean("value"); 
                   return ConstantInt::get(t->type,b);
                } else if(t->type->isIntegerTy()) {
                    uint64_t integer = exp->integer("value");
                    return ConstantInt::get(t->type, integer);
                } else {
                    double dbl = exp->number("value");
                    return ConstantFP::get(t->type, dbl);
                }
            } break;
            case T_cast: {
                Obj a;
                Obj to,from;
                exp->obj("expression",&a);
                exp->obj("to",&to);
                exp->obj("from",&from);
                return emitCast(getType(&from),getType(&to),emitExp(&a));
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
				if(exps.size() == 0) {
					B->CreateRetVoid();
				} else {
					Obj r;
					exps.objAt(0,&r);
					Value * v = emitExp(&r);
					B->CreateRet(v);
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
				stmt->obj("initializers",&inits);
				int N = inits.size();
				for(int i = 0; i < N; i++) {
					Obj init;
					inits.objAt(i,&init);
					rhs.push_back(emitExp(&init));
				}
				Obj vars;
				stmt->obj("variables",&vars);
				N = inits.size();
				for(int i = 0; i < N; i++) {
					Obj v;
					vars.objAt(i,&v);
					AllocaInst * a = allocVar(&v);
					B->CreateStore(rhs[i],a);
				}
			} break;
            case T_assignment: {
                std::vector<Value *> rhsexps;
				Obj rhss;
				stmt->obj("rhs",&rhss);
				int N = rhss.size();
				for(int i = 0; i < N; i++) {
					Obj rhs;
					rhss.objAt(i,&rhs);
					rhsexps.push_back(emitExp(&rhs));
				}
				Obj lhss;
				stmt->obj("lhs",&lhss);
				N = lhss.size();
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
	
	{
		TerraCompiler c;
		c.run(T);
	} //scope to ensure that c.func is destroyed before we pop the reference table off the stack
	
	lua_pop(T->L,1); //remove the reference table from stack
	return 0;
}
