#include "tcompiler.h"
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
	
	//TODO: add optimization passes here
	
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
		lua_rawgeti(L,-1,i);
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
	int64_t integer(const char * field) {
		push();
		lua_getfield(L,-1,field);
		const void * ud = lua_touserdata(L,-1);
		pop(2);
		int64_t i = *(const int64_t*)ud;
		return i;
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
		fprintf(stderr,"getting %d %d\n",ref_table,ref);
		lua_rawgeti(L,ref_table,ref);
	}
	void begin_match(const char * field) {
		pushfield(field);
	}
	int matches(const char * key) {
		lua_pushstring(L,key);
		int e = lua_rawequal(L,-1,-2);
		pop();
		if(e) {
			end_match();
		}
		return e;
	}
	void end_match() {
		pop();
	}
	void setfield(const char * key) { //sets field to value on top of the stack and pops it off
		push();
		lua_pushvalue(L,-2);
		lua_setfield(L,-2,key);
		pop(3);
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

struct Compiler {
	terra_State * T;
	terra_CompilerState * C;
	Obj func;
	TType * getType(Obj * typ) {
		TType * t = (TType*) typ->ud("llvm_type");
		if(t == NULL) {
			t = (TType*) lua_newuserdata(T->L,sizeof(TType));
			memset(t,0,sizeof(TType));
			typ->setfield("llvm_type");
			typ->begin_match("kind");
			if(typ->matches("builtin")) {
				int bytes = typ->number("bytes");
				typ->begin_match("type");
				if(typ->matches("float")) {
					if(bytes == 4) {
						t->type = Type::getFloatTy(*C->ctx);
					} else {
						assert(bytes == 8);
						t->type = Type::getDoubleTy(*C->ctx);
					}
				} else if(typ->matches("integer")) {
					t->issigned = typ->number("signed");
					t->type = Type::getIntNTy(*C->ctx,bytes * 8);
				} else if(typ->matches("logical")) {
					t->type = Type::getInt8Ty(*C->ctx);
					t->islogical = true;
				} else {
					terra_reporterror(T,"type not understood");
					typ->end_match();
				}
			} else if(typ->matches("pointer")) {
				Obj base;
				typ->obj("type",&base);
				t->type = PointerType::getUnqual(getType(&base)->type);
			} else if(typ->matches("functype")) {
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
					rets.objAt(1,&r0);
					TType * r0t = getType(&r0);
					rt = r0t->type;
				} else {
					terra_reporterror(T,"NYI - multiple returns");
				}
				int psz = params.size();
				for(int i = 1; i <= psz; i++) {
					Obj p;
					params.objAt(i,&p);
					TType * pt = getType(&p);
					arguments.push_back(pt->type);
				}
				t->type = FunctionType::get(rt,&arguments[0]); 
			} else {
				typ->end_match();
				terra_reporterror(T,"type not understood");
			}
			assert(t && t->type);
		}
		return t;
	}
	void run(terra_State * _T) {
		T = _T;
		C = T->C;
		//create lua table to hold object references anchored on stack
		lua_newtable(T->L);
		int ref_table = lua_gettop(T->L);
		lua_pushvalue(T->L,-2); //the original argument
		func.initFromStack(T->L, ref_table);
		
		Obj typedtree;
		func.obj("typedtree",&typedtree);
		Obj ftype;
		typedtree.obj("type",&ftype);
		TType * func_type = getType(&ftype);
		const char * name = func.string("name");
		Function * func = Function::Create(cast<FunctionType>(func_type->type), Function::ExternalLinkage,name, C->m);
		//cleanup -- ensure we left the stack the way we started
		assert(lua_gettop(T->L) == ref_table);
	}
};

static int terra_compile(lua_State * L) { //entry point into compiler from lua code
	terra_State * T = (terra_State*) lua_topointer(L,lua_upvalueindex(1));
	assert(T->L == L);
	
	{
		Compiler c;
		c.run(T);
	} //scope to ensure that c.func is destroyed before we pop the reference table off the stack
	
	lua_pop(T->L,1); //remove the reference table from stack
	return 0;
}
