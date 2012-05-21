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
static void terra_compile_llvm(terra_State * T);

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

static int terra_compile(lua_State * L) {
	terra_State * T = (terra_State*) lua_topointer(L,lua_upvalueindex(1));
	assert(T->L == L);
	terra_compile_llvm(T);
	lua_pop(T->L,1); //remove the reference table from stack
	return 0;
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
		const void * ud = lua_topointer(L,-1);
		pop(2);
		int64_t i = *(const int64_t*)ud;
		return i;
	}
	void obj(const char * field, Obj * r) {
		push();
		lua_getfield(L,-1,field);
		r->initFromStack(L,ref_table);
		pop();
	}
	void pushfield(const char * field) {
		push();
		lua_getfield(L,-1,field);
		lua_remove(L,-2);
	}
	void push() {
		lua_rawgeti(L,ref_table,ref);
		const char * str = lua_typename(L,lua_type(L,-1));
	}
	void begin_match(const char * field) {
		pushfield(field);
		const char * str = lua_typename(L,lua_type(L,-1));
	}
	int matches(const char * key) {
		lua_pushstring(L,key);
		int e = lua_rawequal(L,-1,-2);
		pop();
		return e;
	}
	void end_match() {
		pop();
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
	//create lua table to hold object references anchored on stack
	lua_newtable(T->L);
	int ref_table = lua_gettop(T->L);
	lua_pushvalue(T->L,-2); //the original argument
	func.initFromStack(T->L, ref_table);
	
	Obj typed;
	func.obj("typedtree",&typed);
	
	typed.begin_match("kind");
	if(typed.matches("function")) {
		printf("this is a function!!!\n");
	}
	typed.end_match();
	
	//cleanup -- ensure we left the stack the way we started
	assert(lua_gettop(T->L) == ref_table);
}