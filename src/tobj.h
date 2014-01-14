#ifndef _t_obj_h
#define _t_obj_h

extern "C" {
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
}
#include "tkind.h"

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
    bool objAt(int i, Obj * r) {
        push();
        lua_rawgeti(L,-1,i+1); //stick to 0-based indexing in C code...
        if(lua_isnil(L,-1)) {
            pop(2);
            return false;
        }
        r->initFromStack(L,ref_table);
        pop();
        return true;
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
    const char * asstring(const char * field) {
        push();
        lua_getfield(L, LUA_GLOBALSINDEX, "tostring");
        lua_getfield(L,-2,field);
        lua_call(L,1,1);
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
    bool hasfield(const char * field) {
        push();
        lua_getfield(L,-1,field);
        bool isNil = lua_isnil(L,-1);
        pop(2);
        return !isNil;
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
    void clearfield(const char * key) {
        push();
        lua_pushnil(L);
        lua_setfield(L,-2,key);
        pop(1);
    }
    void addentry() {
        int s = size();
        push();
        lua_pushvalue(L, -2);
        lua_rawseti(L, -2, s+1);
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
    void newlist(Obj * lst) {
        lua_getfield(L,LUA_GLOBALSINDEX,"terra");
        lua_getfield(L,-1,"newlist");
        lua_remove(L,-2);
        lua_call(L, 0, 1);
        lst->initFromStack(L, ref_table);
    }
    void fromStack(Obj * o) {
        o->initFromStack(L, ref_table);
    }
    lua_State * getState() {
        return L;
    }
    int getRefTable() {
        return ref_table;
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

static inline int lobj_newreftable(lua_State * L) {
    lua_newtable(L);
    return lua_gettop(L);
}

static inline void lobj_removereftable(lua_State * L, int ref_table) {
    assert(lua_gettop(L) == ref_table);
    lua_pop(L,1); //remove the reference table from stack
}

#endif
