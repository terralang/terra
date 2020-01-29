/* vim: ts=4 sw=4 sts=4 et tw=78
 * Copyright (c) 2011 James R. McKaskill. See license in tffi.h
 */
#include "tffi.h"
#include <math.h>
#include <inttypes.h>

/* Set to 1 to get extra debugging on print */
#define DEBUG_TOSTRING 0

int jit_key;
int ctype_mt_key;
int cdata_mt_key;
int callback_mt_key;
int cmodule_mt_key;
int constants_key;
int types_key;
int gc_key;
int callbacks_key;
int functions_key;
int abi_key;
int next_unnamed_key;
int niluv_key;
int asmname_key;

#if LUA_VERSION_NUM == 501
/*
** set functions from list 'l' into table at top - 'nup'; each
** function gets the 'nup' elements at the top as upvalues.
** Returns with only the table at the stack.
*/
static void luaL_setfuncs(lua_State* L, const luaL_Reg* l, int nup) {
    luaL_checkstack(L, nup, "too many upvalues");
    for (; l && l->name; l++) { /* fill the table with given functions */
        int i;
        for (i = 0; i < nup; i++) /* copy upvalues to the top */
            lua_pushvalue(L, -nup);
        lua_pushcclosure(L, l->func, nup); /* closure with those upvalues */
        lua_setfield(L, -(nup + 2), l->name);
    }
    lua_pop(L, nup); /* remove upvalues */
}
#endif

void push_upval(lua_State* L, int* key) {
    lua_pushlightuserdata(L, key);
    lua_rawget(L, LUA_REGISTRYINDEX);
}

void set_upval(lua_State* L, int* key) {
    lua_pushlightuserdata(L, key);
    lua_insert(L, -2);
    lua_rawset(L, LUA_REGISTRYINDEX);
}

int equals_upval(lua_State* L, int idx, int* key) {
    int ret;
    lua_pushvalue(L, idx);
    push_upval(L, key);
    ret = lua_rawequal(L, -2, -1);
    lua_pop(L, 2);
    return ret;
}

static int type_error(lua_State* L, int idx, const char* to_type, int to_usr,
                      const struct ctype* to_ct) {
    luaL_Buffer B;
    struct ctype ft;

    assert(to_type || (to_usr && to_ct));
    if (to_usr) {
        to_usr = lua_absindex(L, to_usr);
    }

    idx = lua_absindex(L, idx);

    luaL_buffinit(L, &B);
    to_cdata(L, idx, &ft);

    if (ft.type != INVALID_TYPE) {
        push_type_name(L, -1, &ft);
        lua_pushfstring(L, "unable to convert argument %d from cdata<%s> to cdata<", idx,
                        lua_tostring(L, -1));
        lua_remove(L, -2);
        luaL_addvalue(&B);
    } else {
        lua_pushfstring(L, "unable to convert argument %d from lua<%s> to cdata<", idx,
                        luaL_typename(L, idx));
        luaL_addvalue(&B);
    }

    if (to_ct) {
        push_type_name(L, to_usr, to_ct);
        luaL_addvalue(&B);
    } else {
        luaL_addstring(&B, to_type);
    }

    luaL_addchar(&B, '>');

    luaL_pushresult(&B);
    return lua_error(L);
}

static int64_t check_intptr(lua_State* L, int idx, void* p, struct ctype* ct) {
    if (ct->type == INVALID_TYPE) {
        int64_t ret;
        memset(ct, 0, sizeof(*ct));
        ct->base_size = 8;
        ct->type = INT64_TYPE;
        ct->is_defined = 1;
        ret = luaL_checknumber(L, idx);
        return ret;

    } else if (ct->pointers) {
        return (intptr_t)p;
    }

    switch (ct->type) {
        case INTPTR_TYPE:
        case FUNCTION_PTR_TYPE:
            return *(intptr_t*)p;

        case INT64_TYPE:
            return *(int64_t*)p;

        case INT32_TYPE:
            return ct->is_unsigned ? (int64_t) * (uint32_t*)p : (int64_t) * (int32_t*)p;

        case INT16_TYPE:
            return ct->is_unsigned ? (int64_t) * (uint16_t*)p : (int64_t) * (int16_t*)p;

        case INT8_TYPE:
            return ct->is_unsigned ? (int64_t) * (uint8_t*)p : (int64_t) * (int8_t*)p;

        default:
            type_error(L, idx, "intptr_t", 0, NULL);
            return 0;
    }
}

#define TO_NUMBER(TYPE, ALLOW_POINTERS)                                                  \
    TYPE real = 0, imag = 0;                                                             \
    void* p;                                                                             \
    struct ctype ct;                                                                     \
                                                                                         \
    switch (lua_type(L, idx)) {                                                          \
        case LUA_TBOOLEAN:                                                               \
            real = (TYPE)lua_toboolean(L, idx);                                          \
            break;                                                                       \
                                                                                         \
        case LUA_TNUMBER:                                                                \
            real = (TYPE)lua_tonumber(L, idx);                                           \
            break;                                                                       \
                                                                                         \
        case LUA_TSTRING:                                                                \
            if (!ALLOW_POINTERS) {                                                       \
                type_error(L, idx, #TYPE, 0, NULL);                                      \
            }                                                                            \
            real = (TYPE)(intptr_t)lua_tostring(L, idx);                                 \
            break;                                                                       \
                                                                                         \
        case LUA_TLIGHTUSERDATA:                                                         \
            if (!ALLOW_POINTERS) {                                                       \
                type_error(L, idx, #TYPE, 0, NULL);                                      \
            }                                                                            \
            real = (TYPE)(intptr_t)lua_topointer(L, idx);                                \
            break;                                                                       \
                                                                                         \
        case LUA_TUSERDATA:                                                              \
            p = to_cdata(L, idx, &ct);                                                   \
                                                                                         \
            if (ct.type == INVALID_TYPE) {                                               \
                if (!ALLOW_POINTERS) {                                                   \
                    type_error(L, idx, #TYPE, 0, NULL);                                  \
                }                                                                        \
                real = (TYPE)(intptr_t)p;                                                \
            } else if (ct.pointers || ct.type == STRUCT_TYPE || ct.type == UNION_TYPE) { \
                if (!ALLOW_POINTERS) {                                                   \
                    type_error(L, idx, #TYPE, 0, NULL);                                  \
                }                                                                        \
                real = (TYPE)(intptr_t)p;                                                \
            } else if (ct.type == COMPLEX_DOUBLE_TYPE) {                                 \
                real = (TYPE)creal(*(complex_double*)p);                                 \
                imag = (TYPE)cimag(*(complex_double*)p);                                 \
            } else if (ct.type == COMPLEX_FLOAT_TYPE) {                                  \
                real = (TYPE)crealf(*(complex_float*)p);                                 \
                imag = (TYPE)cimagf(*(complex_float*)p);                                 \
            } else if (ct.type == DOUBLE_TYPE) {                                         \
                real = (TYPE) * (double*)p;                                              \
            } else if (ct.type == FLOAT_TYPE) {                                          \
                real = (TYPE) * (float*)p;                                               \
            } else {                                                                     \
                real = check_intptr(L, idx, p, &ct);                                     \
            }                                                                            \
            lua_pop(L, 1);                                                               \
            break;                                                                       \
                                                                                         \
        case LUA_TNIL:                                                                   \
            real = (TYPE)0;                                                              \
            break;                                                                       \
                                                                                         \
        default:                                                                         \
            type_error(L, idx, #TYPE, 0, NULL);                                          \
    }

static int64_t cast_int64(lua_State* L, int idx, int is_cast) {
    TO_NUMBER(int64_t, is_cast);
    (void)imag;
    return real;
}

static uint64_t cast_uint64(lua_State* L, int idx, int is_cast) {
    TO_NUMBER(uint64_t, is_cast);
    (void)imag;
    return real;
}

int32_t check_int32(lua_State* L, int idx) { return (int32_t)cast_int64(L, idx, 0); }

uint32_t check_uint32(lua_State* L, int idx) { return (uint32_t)cast_uint64(L, idx, 0); }

int64_t check_int64(lua_State* L, int idx) { return cast_int64(L, idx, 0); }

uint64_t check_uint64(lua_State* L, int idx) { return cast_uint64(L, idx, 0); }

static void do_check_double(lua_State* L, int idx, double* preal, double* pimag) {
    TO_NUMBER(double, 0);
    if (preal) *preal = real;
    if (pimag) *pimag = imag;
}

double check_double(lua_State* L, int idx) {
    double ret;
    do_check_double(L, idx, &ret, NULL);
    return ret;
}

float check_float(lua_State* L, int idx) {
    double ret;
    do_check_double(L, idx, &ret, NULL);
    return ret;
}

uintptr_t check_uintptr(lua_State* L, int idx) {
    TO_NUMBER(uintptr_t, 1);
    (void)imag;
    return real;
}

#ifdef HAVE_COMPLEX
complex_double check_complex_double(lua_State* L, int idx) {
    double real, imag;
    do_check_double(L, idx, &real, &imag);
    return real + imag * 1i;
}

complex_float check_complex_float(lua_State* L, int idx) {
    double real, imag;
    do_check_double(L, idx, &real, &imag);
    return real + imag * 1i;
}

#else
complex_double check_complex_double(lua_State* L, int idx) {
    complex_double c;
    do_check_double(L, idx, &c.real, &c.imag);
    return c;
}

complex_float check_complex_float(lua_State* L, int idx) {
    complex_double d;
    complex_float f;
    do_check_double(L, idx, &d.real, &d.imag);
    f.real = d.real;
    f.imag = d.imag;
    return f;
}
#endif

static size_t unpack_vararg(lua_State* L, int i, char* to) {
    void* p;
    struct ctype ct;

    switch (lua_type(L, i)) {
        case LUA_TBOOLEAN:
            *(int*)to = lua_toboolean(L, i);
            return sizeof(int);

        case LUA_TNUMBER:
            *(double*)to = lua_tonumber(L, i);
            return sizeof(double);

        case LUA_TSTRING:
            *(const char**)to = lua_tostring(L, i);
            return sizeof(const char*);

        case LUA_TLIGHTUSERDATA:
            *(void**)to = lua_touserdata(L, i);
            return sizeof(void*);

        case LUA_TUSERDATA:
            p = to_cdata(L, i, &ct);

            if (ct.type == INVALID_TYPE) {
                *(void**)to = p;
                return sizeof(void*);
            }

            lua_pop(L, 1);

            if (ct.pointers || ct.type == INTPTR_TYPE) {
                *(void**)to = p;
                return sizeof(void*);

            } else if (ct.type == INT32_TYPE) {
                *(int32_t*)to = *(int32_t*)p;
                return sizeof(int32_t);

            } else if (ct.type == INT64_TYPE) {
                *(int64_t*)to = *(int64_t*)p;
                return sizeof(int64_t);
            }
            goto err;

        case LUA_TNIL:
            *(void**)to = NULL;
            return sizeof(void*);

        default:
            goto err;
    }

err:
    return type_error(L, i, "vararg", 0, NULL);
}

void unpack_varargs_stack(lua_State* L, int first, int last, char* to) {
    int i;

    for (i = first; i <= last; i++) {
        to += unpack_vararg(L, i, to);
    }
}

void unpack_varargs_stack_skip(lua_State* L, int first, int last, int ints_to_skip,
                               int floats_to_skip, char* to) {
    int i;

    for (i = first; i <= last; i++) {
        int type = lua_type(L, i);

        if (type == LUA_TNUMBER && --floats_to_skip >= 0) {
            continue;
        } else if (type != LUA_TNUMBER && --ints_to_skip >= 0) {
            continue;
        }

        to += unpack_vararg(L, i, to);
    }
}

void unpack_varargs_float(lua_State* L, int first, int last, int max, char* to) {
    int i;

    for (i = first; i <= last && max > 0; i++) {
        if (lua_type(L, i) == LUA_TNUMBER) {
            unpack_vararg(L, i, to);
            to += sizeof(double);
            max--;
        }
    }
}

void unpack_varargs_int(lua_State* L, int first, int last, int max, char* to) {
    int i;

    for (i = first; i <= last && max > 0; i++) {
        if (lua_type(L, i) != LUA_TNUMBER) {
            unpack_vararg(L, i, to);
            to += sizeof(void*);
            max--;
        }
    }
}

void unpack_varargs_reg(lua_State* L, int first, int last, char* to) {
    int i;

    for (i = first; i <= last; i++) {
        unpack_vararg(L, i, to);
        to += sizeof(double);
    }
}

/* to_enum tries to convert a value at idx to the enum type indicated by to_ct
 * and uv to_usr. For strings this means it will do a string lookup for the
 * enum type. It leaves the stack unchanged. Will throw an error if the type
 * at idx can't be conerted.
 */
int32_t check_enum(lua_State* L, int idx, int to_usr, const struct ctype* to_ct) {
    int32_t ret;

    switch (lua_type(L, idx)) {
        case LUA_TSTRING:
            /* lookup string in to_usr to find value */
            to_usr = lua_absindex(L, to_usr);
            lua_pushvalue(L, idx);
            lua_rawget(L, to_usr);

            if (lua_isnil(L, -1)) {
                goto err;
            }

            ret = (int32_t)lua_tointeger(L, -1);
            lua_pop(L, 1);
            return ret;

        case LUA_TUSERDATA:
            return check_int32(L, idx);

        case LUA_TNIL:
            return (int32_t)0;

        case LUA_TNUMBER:
            return (int32_t)lua_tointeger(L, idx);

        default:
            goto err;
    }

err:
    return type_error(L, idx, NULL, to_usr, to_ct);
}

/* to_pointer tries converts a value at idx to a pointer. It fills out ct and
 * pushes the uv of the found type. It will throw a lua error if it can not
 * convert the value to a pointer. */
static void* check_pointer(lua_State* L, int idx, struct ctype* ct) {
    void* p;
    memset(ct, 0, sizeof(*ct));
    ct->pointers = 1;
    idx = lua_absindex(L, idx);

    switch (lua_type(L, idx)) {
        case LUA_TNIL:
            ct->type = VOID_TYPE;
            ct->is_null = 1;
            lua_pushnil(L);
            return NULL;

        case LUA_TNUMBER:
            ct->type = INTPTR_TYPE;
            ct->is_unsigned = 1;
            ct->pointers = 0;
            lua_pushnil(L);
            return (void*)(uintptr_t)lua_tonumber(L, idx);

        case LUA_TLIGHTUSERDATA:
            ct->type = VOID_TYPE;
            lua_pushnil(L);
            return lua_touserdata(L, idx);

        case LUA_TSTRING:
            ct->type = INT8_TYPE;
            ct->is_unsigned = IS_CHAR_UNSIGNED;
            ct->is_array = 1;
            ct->base_size = 1;
            ct->const_mask = 2;
            lua_pushnil(L);
            return (void*)lua_tolstring(L, idx, &ct->array_size);

        case LUA_TUSERDATA:
            p = to_cdata(L, idx, ct);

            if (ct->type == INVALID_TYPE) {
                /* some other type of user data */
                ct->type = VOID_TYPE;
                return lua_touserdata(L, idx);
            } else if (ct->type == STRUCT_TYPE || ct->type == UNION_TYPE) {
                return p;
            } else {
                return (void*)(intptr_t)check_intptr(L, idx, p, ct);
            }
            break;
    }

    type_error(L, idx, "pointer", 0, NULL);
    return NULL;
}

static int is_void_ptr(const struct ctype* ct) {
    return ct->type == VOID_TYPE && ct->pointers == 1;
}

static int is_same_type(lua_State* L, int usr1, int usr2, const struct ctype* t1,
                        const struct ctype* t2) {
    if (t1->type != t2->type) {
        return 0;
    }

#if LUA_VERSION_NUM == 501
    if (lua_isnil(L, usr1) != lua_isnil(L, usr2)) {
        int ret;
        usr1 = lua_absindex(L, usr1);
        usr2 = lua_absindex(L, usr2);
        push_upval(L, &niluv_key);

        ret = lua_rawequal(L, usr1, -1) || lua_rawequal(L, usr2, -1);

        lua_pop(L, 1);

        if (ret) {
            return 1;
        }
    }
#endif

    return lua_rawequal(L, usr1, usr2);
}

static void set_struct(lua_State* L, int idx, void* to, int to_usr,
                       const struct ctype* tt, int check_pointers);

/* to_typed_pointer converts a value at idx to a type tt with target uv to_usr
 * checking all types. May push a temporary value so that it can create
 * structs on the fly. */
void* check_typed_pointer(lua_State* L, int idx, int to_usr, const struct ctype* tt) {
    struct ctype ft;
    void* p;

    to_usr = lua_absindex(L, to_usr);
    idx = lua_absindex(L, idx);

    if (tt->pointers == 1 && (tt->type == STRUCT_TYPE || tt->type == UNION_TYPE) &&
        lua_type(L, idx) == LUA_TTABLE) {
        /* need to construct a struct of the target type */
        struct ctype ct = *tt;
        ct.pointers = ct.is_array = 0;
        p = push_cdata(L, to_usr, &ct);
        set_struct(L, idx, p, to_usr, &ct, 1);
        return p;
    }

    p = check_pointer(L, idx, &ft);

    if (tt->pointers == 1 && ft.pointers == 0 &&
        (ft.type == STRUCT_TYPE || ft.type == UNION_TYPE)) {
        /* auto dereference structs */
        ft.pointers = 1;
        ft.const_mask <<= 1;
    }

    if (is_void_ptr(tt)) {
        /* any pointer can convert to void* */
        goto suc;

    } else if (ft.is_null) {
        /* NULL can convert to any pointer */
        goto suc;

    } else if (!is_same_type(L, to_usr, -1, tt, &ft)) {
        /* the base type is different */
        goto err;

    } else if (tt->pointers != ft.pointers) {
        goto err;

    } else if (ft.const_mask & ~tt->const_mask) {
        /* for every const in from it must be in to, there are further rules
         * for const casting (see the c++ spec), but they are hard to test
         * quickly */
        goto err;
    }

suc:
    return p;

err:
    type_error(L, idx, NULL, to_usr, tt);
    return NULL;
}

/* to_cfunction converts a value at idx with usr table at to_usr and type tt
 * into a function. Leaves the stack unchanged. */
static cfunction check_cfunction(lua_State* L, int idx, int to_usr,
                                 const struct ctype* tt, int check_pointers) {
    void* p;
    struct ctype ft;
    int top = lua_gettop(L);

    idx = lua_absindex(L, idx);
    to_usr = lua_absindex(L, to_usr);

    switch (lua_type(L, idx)) {
        case LUA_TFUNCTION:
            assert(!"callbacks are unimplemented");
            return NULL;

        case LUA_TNIL:
            return NULL;

        case LUA_TLIGHTUSERDATA:
            if (check_pointers) {
                goto err;
            } else {
                return (cfunction)lua_touserdata(L, idx);
            }

        case LUA_TUSERDATA:
            p = to_cdata(L, idx, &ft);
            assert(lua_gettop(L) == top + 1);

            if (ft.type == INVALID_TYPE) {
                if (check_pointers) {
                    goto err;
                } else {
                    lua_pop(L, 1);
                    return (cfunction)lua_touserdata(L, idx);
                }

            } else if (ft.is_null) {
                lua_pop(L, 1);
                return NULL;

            } else if (!check_pointers && (ft.pointers || ft.type == INTPTR_TYPE)) {
                lua_pop(L, 1);
                return (cfunction) * (void**)p;

            } else if (ft.type != FUNCTION_PTR_TYPE) {
                goto err;

            } else if (!check_pointers) {
                lua_pop(L, 1);
                return *(cfunction*)p;

            } else if (ft.calling_convention != tt->calling_convention) {
                goto err;

            } else if (!is_same_type(L, -1, to_usr, &ft, tt)) {
                goto err;

            } else {
                lua_pop(L, 1);
                return *(cfunction*)p;
            }

        default:
            goto err;
    }

err:
    type_error(L, idx, NULL, to_usr, tt);
    return NULL;
}

/* to_type_cfunction converts a value at idx with uv at to_usr and type tt to
 * a cfunction. Leaves the stack unchanged. */
cfunction check_typed_cfunction(lua_State* L, int idx, int to_usr,
                                const struct ctype* tt) {
    return check_cfunction(L, idx, to_usr, tt, 1);
}

static void set_value(lua_State* L, int idx, void* to, int to_usr, const struct ctype* tt,
                      int check_pointers);

static void set_array(lua_State* L, int idx, void* to, int to_usr, const struct ctype* tt,
                      int check_pointers) {
    size_t i, sz, esz;
    struct ctype et;

    idx = lua_absindex(L, idx);
    to_usr = lua_absindex(L, to_usr);

    switch (lua_type(L, idx)) {
        case LUA_TSTRING:
            if (tt->pointers == 1 && tt->type == INT8_TYPE) {
                const char* str = lua_tolstring(L, idx, &sz);

                if (!tt->is_variable_array && sz >= tt->array_size) {
                    memcpy(to, str, tt->array_size);
                } else {
                    /* include nul terminator */
                    memcpy(to, str, sz + 1);
                }
            } else {
                goto err;
            }
            break;

        case LUA_TTABLE:
            et = *tt;
            et.pointers--;
            et.const_mask >>= 1;
            et.is_array = 0;
            esz = et.pointers ? sizeof(void*) : et.base_size;

            lua_rawgeti(L, idx, 2);

            if (tt->is_variable_array) {
                /* we have no idea how big the array is, so set values based off
                 * how many items were given to us */
                lua_pop(L, 1);
                for (i = 0; i < lua_rawlen(L, idx); i++) {
                    lua_rawgeti(L, idx, (int)i + 1);
                    set_value(L, -1, (char*)to + esz * i, to_usr, &et, check_pointers);
                    lua_pop(L, 1);
                }

            } else if (lua_isnil(L, -1)) {
                /* there is no second element, so we set the whole array to the
                 * first element (or nil - ie 0) if there is no first element) */
                lua_pop(L, 1);
                lua_rawgeti(L, idx, 1);

                if (lua_isnil(L, -1)) {
                    memset(to, 0, ctype_size(L, tt));
                } else {
                    /* if its still variable we have no idea how many values to set */
                    for (i = 0; i < tt->array_size; i++) {
                        set_value(L, -1, (char*)to + esz * i, to_usr, &et,
                                  check_pointers);
                    }
                }

                lua_pop(L, 1);

            } else {
                /* there is a second element, so we set each element using the
                 * equiv index in the table initializer */
                lua_pop(L, 1);
                for (i = 0; i < tt->array_size; i++) {
                    lua_rawgeti(L, idx, (int)(i + 1));

                    if (lua_isnil(L, -1)) {
                        /* we've hit the end of the values provided in the
                         * initializer, so memset the rest to zero */
                        lua_pop(L, 1);
                        memset((char*)to + esz * i, 0, (tt->array_size - i) * esz);
                        break;

                    } else {
                        set_value(L, -1, (char*)to + esz * i, to_usr, &et,
                                  check_pointers);
                        lua_pop(L, 1);
                    }
                }
            }
            break;

        default:
            goto err;
    }

    return;

err:
    type_error(L, idx, NULL, to_usr, tt);
}

/* pops the member key from the stack, leaves the member user value on the
 * stack. Returns the member offset. Returns -ve if the member can not be
 * found. */
static ptrdiff_t get_member(lua_State* L, int usr, const struct ctype* ct,
                            struct ctype* mt) {
    ptrdiff_t off;
    lua_rawget(L, usr);

    if (lua_isnil(L, -1)) {
        lua_pop(L, 1);
        return -1;
    }

    *mt = *(const struct ctype*)lua_touserdata(L, -1);
    lua_getuservalue(L, -1);
    lua_replace(L, -2);

    if (mt->is_variable_array && ct->variable_size_known) {
        /* eg char mbr[?] */
        size_t sz = (mt->pointers > 1) ? sizeof(void*) : mt->base_size;
        assert(ct->is_variable_struct && mt->is_array);
        mt->array_size = ct->variable_increment / sz;
        mt->is_variable_array = 0;

    } else if (mt->is_variable_struct && ct->variable_size_known) {
        /* eg struct {char a; char b[?]} mbr; */
        assert(ct->is_variable_struct);
        mt->variable_size_known = 1;
        mt->variable_increment = ct->variable_increment;
    }

    off = mt->offset;
    mt->offset = 0;
    return off;
}

static void set_struct(lua_State* L, int idx, void* to, int to_usr,
                       const struct ctype* tt, int check_pointers) {
    int have_first = 0;
    int have_other = 0;
    struct ctype mt;
    void* p;

    to_usr = lua_absindex(L, to_usr);
    idx = lua_absindex(L, idx);

    switch (lua_type(L, idx)) {
        case LUA_TTABLE:
            /* match up to the members based off the table initializers key - this
             * will match both numbered and named members in the user table
             * we need a special case for when no entries in the initializer -
             * zero initialize the c struct, and only one entry in the initializer
             * - set all members to this value */
            memset(to, 0, ctype_size(L, tt));
            lua_pushnil(L);
            while (lua_next(L, idx)) {
                ptrdiff_t off;

                if (!have_first && lua_tonumber(L, -2) == 1 && lua_tonumber(L, -1) != 0) {
                    have_first = 1;
                } else if (!have_other &&
                           (lua_type(L, -2) != LUA_TNUMBER || lua_tonumber(L, -2) != 1)) {
                    have_other = 1;
                }

                lua_pushvalue(L, -2);
                off = get_member(L, to_usr, tt, &mt);
                assert(off >= 0);
                set_value(L, -2, (char*)to + off, -1, &mt, check_pointers);

                /* initializer value, mt usr */
                lua_pop(L, 2);
            }

            /* if we only had a single non zero value then initialize all members to that
             * value */
            if (!have_other && have_first && tt->type != UNION_TYPE) {
                size_t i, sz;
                ptrdiff_t off;
                lua_rawgeti(L, idx, 1);
                sz = lua_rawlen(L, to_usr);

                for (i = 2; i < sz; i++) {
                    lua_pushnumber(L, i);
                    off = get_member(L, to_usr, tt, &mt);
                    assert(off >= 0);
                    set_value(L, -2, (char*)to + off, -1, &mt, check_pointers);
                    lua_pop(L, 1); /* mt usr */
                }

                lua_pop(L, 1); /* initializer table */
            }
            break;

        case LUA_TUSERDATA:
            if (check_pointers) {
                p = check_typed_pointer(L, idx, to_usr, tt);
            } else {
                struct ctype ct;
                p = check_pointer(L, idx, &ct);
            }
            memcpy(to, p, tt->base_size);
            lua_pop(L, 1);
            break;

        default:
            goto err;
    }

    return;

err:
    type_error(L, idx, NULL, to_usr, tt);
}

static void set_value(lua_State* L, int idx, void* to, int to_usr, const struct ctype* tt,
                      int check_pointers) {
    int top = lua_gettop(L);

    if (tt->is_array) {
        set_array(L, idx, to, to_usr, tt, check_pointers);

    } else if (tt->pointers) {
        union {
            uint8_t c[sizeof(void*)];
            void* p;
        } u;

        if (lua_istable(L, idx)) {
            luaL_error(L,
                       "Can't set a pointer member to a struct that's about to be freed");
        }

        if (check_pointers) {
            u.p = check_typed_pointer(L, idx, to_usr, tt);
        } else {
            struct ctype ct;
            u.p = check_pointer(L, idx, &ct);
        }

#ifndef ALLOW_MISALIGNED_ACCESS
        if ((uintptr_t)to & PTR_ALIGN_MASK) {
            memcpy(to, u.c, sizeof(void*));
        } else
#endif
        {
            *(void**)to = u.p;
        }

        lua_pop(L, 1);

    } else if (tt->is_bitfield) {
        uint64_t hi_mask = UINT64_C(0) - (UINT64_C(1) << (tt->bit_offset + tt->bit_size));
        uint64_t low_mask = (UINT64_C(1) << tt->bit_offset) - UINT64_C(1);
        uint64_t val = check_uint64(L, idx);
        val &= (UINT64_C(1) << tt->bit_size) - 1;
        val <<= tt->bit_offset;
        *(uint64_t*)to = val | (*(uint64_t*)to & (hi_mask | low_mask));

    } else if (tt->type == STRUCT_TYPE || tt->type == UNION_TYPE) {
        set_struct(L, idx, to, to_usr, tt, check_pointers);

    } else {
#ifndef ALLOW_MISALIGNED_ACCESS
        union {
            uint8_t c[8];
            _Bool b;
            uint64_t u64;
            float f;
            double d;
            cfunction func;
        } misalign;

        void* origto = to;

        if ((uintptr_t)origto & (tt->base_size - 1)) {
            to = misalign.c;
        }
#endif

        switch (tt->type) {
            case BOOL_TYPE:
                *(_Bool*)to = (cast_int64(L, idx, !check_pointers) != 0);
                break;
            case INT8_TYPE:
                if (tt->is_unsigned) {
                    *(uint8_t*)to = (uint8_t)cast_uint64(L, idx, !check_pointers);
                } else {
                    *(int8_t*)to = (int8_t)cast_int64(L, idx, !check_pointers);
                }
                break;
            case INT16_TYPE:
                if (tt->is_unsigned) {
                    *(uint16_t*)to = (uint16_t)cast_uint64(L, idx, !check_pointers);
                } else {
                    *(int16_t*)to = (int16_t)cast_int64(L, idx, !check_pointers);
                }
                break;
            case INT32_TYPE:
                if (tt->is_unsigned) {
                    *(uint32_t*)to = (uint32_t)cast_uint64(L, idx, !check_pointers);
                } else {
                    *(int32_t*)to = (int32_t)cast_int64(L, idx, !check_pointers);
                }
                break;
            case INT64_TYPE:
                if (tt->is_unsigned) {
                    *(uint64_t*)to = cast_uint64(L, idx, !check_pointers);
                } else {
                    *(int64_t*)to = cast_int64(L, idx, !check_pointers);
                }
                break;
            case FLOAT_TYPE:
                *(float*)to = (float)check_double(L, idx);
                break;
            case DOUBLE_TYPE:
                *(double*)to = check_double(L, idx);
                break;
            case COMPLEX_FLOAT_TYPE:
                *(complex_float*)to = check_complex_float(L, idx);
                break;
            case COMPLEX_DOUBLE_TYPE:
                *(complex_double*)to = check_complex_double(L, idx);
                break;
            case INTPTR_TYPE:
                *(uintptr_t*)to = check_uintptr(L, idx);
                break;
            case ENUM_TYPE:
                *(int32_t*)to = check_enum(L, idx, to_usr, tt);
                break;
            case FUNCTION_PTR_TYPE:
                *(cfunction*)to = check_cfunction(L, idx, to_usr, tt, check_pointers);
                break;
            default:
                goto err;
        }

#ifndef ALLOW_MISALIGNED_ACCESS
        if ((uintptr_t)origto & (tt->base_size - 1)) {
            memcpy(origto, misalign.c, tt->base_size);
        }
#endif
    }

    assert(lua_gettop(L) == top);
    return;
err:
    type_error(L, idx, NULL, to_usr, tt);
}

static int ffi_typeof(lua_State* L) {
    struct ctype ct;
    check_ctype(L, 1, &ct);
    push_ctype(L, -1, &ct);
    return 1;
}

static void setmintop(lua_State* L, int idx) {
    if (lua_gettop(L) < idx) {
        lua_settop(L, idx);
    }
}

/* warning: in the case that it finds an array size, it removes that index */
static void get_variable_array_size(lua_State* L, int idx, struct ctype* ct) {
    /* we only care about the variable buisness for the variable array
     * directly ie ffi.new('char[?]') or the struct that contains the variable
     * array ffi.new('struct {char v[?]}'). A pointer to the struct doesn't
     * care about the variable size (it treats it as a zero sized array). */

    if (ct->is_variable_array) {
        assert(ct->is_array);
        ct->array_size = (size_t)luaL_checknumber(L, idx);
        ct->is_variable_array = 0;
        lua_remove(L, idx);

    } else if (ct->is_variable_struct && !ct->variable_size_known) {
        assert(ct->type == STRUCT_TYPE && !ct->is_array);
        ct->variable_increment *= (size_t)luaL_checknumber(L, idx);
        ct->variable_size_known = 1;
        lua_remove(L, idx);
    }
}

static int try_set_value(lua_State* L) {
    void* p = lua_touserdata(L, 2);
    struct ctype* ct = (struct ctype*)lua_touserdata(L, 4);
    int check_ptrs = lua_toboolean(L, 5);
    set_value(L, 1, p, 3, ct, check_ptrs);
    return 0;
}

static int do_new(lua_State* L, int is_cast) {
    int cargs, i;
    void* p;
    struct ctype ct;
    int check_ptrs = !is_cast;

    check_ctype(L, 1, &ct);

    /* don't push a callback when we have a c function, as cb:set needs a
     * compiled callback from a lua function to work */
    if (!ct.pointers && ct.type == FUNCTION_PTR_TYPE &&
        (lua_isnil(L, 2) || lua_isfunction(L, 2))) {
        assert(!"callbacks are not implemented");
        return 1;
    }

    /* this removes the vararg argument if its needed, and errors if its invalid */
    if (!is_cast) {
        get_variable_array_size(L, 2, &ct);
    }

    p = push_cdata(L, -1, &ct);

    /* if the user mt has a __gc function then call ffi.gc on this value */
    if (push_user_mt(L, -2, &ct)) {
        push_upval(L, &gc_key);
        lua_pushvalue(L, -3);

        /* user_mt.__gc */
        lua_pushliteral(L, "__gc");
        lua_rawget(L, -4);

        lua_rawset(L, -3); /* gc_upval[cdata] = user_mt.__gc */
        lua_pop(L, 2);     /* user_mt and gc_upval */
    }

    /* stack is:
     * ctype arg
     * ctor args ... 0+
     * ctype usr
     * cdata
     */

    cargs = lua_gettop(L) - 3;

    if (cargs == 0) {
        return 1;
    }

    if (cargs == 1) {
        /* try packed form first
         * packed: ffi.new('int[3]', {1})
         * unpacked: ffi.new('int[3]', 1)
         */
        lua_pushcfunction(L, &try_set_value);
        lua_pushvalue(L, 2); /* ctor arg */
        lua_pushlightuserdata(L, p);
        lua_pushvalue(L, -5); /* ctype usr */
        lua_pushlightuserdata(L, &ct);
        lua_pushboolean(L, check_ptrs);

        if (!lua_pcall(L, 5, 0, 0)) {
            return 1;
        }

        /* remove any errors */
        lua_settop(L, 4);
    }

    /* if we have more than 2 ctor arguments then they must be unpacked, e.g.
     * ffi.new('int[3]', 1, 2, 3) */
    lua_createtable(L, cargs, 0);
    lua_replace(L, 1);
    for (i = 1; i <= cargs; i++) {
        lua_pushvalue(L, i + 1);
        lua_rawseti(L, 1, i);
    }
    assert(lua_gettop(L) == cargs + 3);
    set_value(L, 1, p, -2, &ct, check_ptrs);

    return 1;
}

static int ffi_new(lua_State* L) { return do_new(L, 0); }

static int ffi_cast(lua_State* L) { return do_new(L, 1); }

static int ctype_new(lua_State* L) { return do_new(L, 0); }

static int ctype_call(lua_State* L) {
    struct ctype ct;
    int top = lua_gettop(L);

    check_ctype(L, 1, &ct);

    if (push_user_mt(L, -1, &ct)) {
        lua_pushstring(L, "__new");
        lua_rawget(L, -2);
        if (!lua_isnil(L, -1)) {
            lua_insert(L, 1);  // function at bottom of stack under args
            lua_pop(L, 2);
            lua_call(L, top, 1);
            return 1;
        }
        lua_pop(L, 2);
    }
    lua_pop(L, 1);

    assert(lua_gettop(L) == top);
    return do_new(L, 0);
}

static int ffi_sizeof(lua_State* L) {
    struct ctype ct;
    check_ctype(L, 1, &ct);
    get_variable_array_size(L, 2, &ct);
    lua_pushnumber(L, ctype_size(L, &ct));
    return 1;
}

static int ffi_alignof(lua_State* L) {
    struct ctype ct, mt;
    lua_settop(L, 2);
    check_ctype(L, 1, &ct);

    /* if no member is specified then we return the alignment of the type */
    if (lua_isnil(L, 2)) {
        lua_pushnumber(L, ct.align_mask + 1);
        return 1;
    }

    /* get the alignment of the member */
    lua_pushvalue(L, 2);
    if (get_member(L, -2, &ct, &mt) < 0) {
        push_type_name(L, 3, &ct);
        return luaL_error(L, "type %s has no member %s", lua_tostring(L, -1),
                          lua_tostring(L, 2));
    }

    lua_pushnumber(L, mt.align_mask + 1);
    return 1;
}

static int ffi_offsetof(lua_State* L) {
    ptrdiff_t off;
    struct ctype ct, mt;
    lua_settop(L, 2);
    check_ctype(L, 1, &ct);

    lua_pushvalue(L, 2);
    off = get_member(L, -2, &ct,
                     &mt); /* this replaces the member key at -1 with the mbr usr value */
    if (off < 0) {
        push_type_name(L, 3, &ct);
        return luaL_error(L, "type %s has no member %s", lua_tostring(L, -1),
                          lua_tostring(L, 2));
    }

    lua_pushnumber(L, off);

    if (!mt.is_bitfield) {
        return 1;
    }

    lua_pushnumber(L, mt.bit_offset);
    lua_pushnumber(L, mt.bit_size);
    return 3;
}

static int ffi_istype(lua_State* L) {
    struct ctype tt, ft;
    check_ctype(L, 1, &tt);
    to_cdata(L, 2, &ft);

    if (ft.type == INVALID_TYPE) {
        goto fail;
    }

    if (!is_same_type(L, 3, 4, &tt, &ft)) {
        goto fail;
    }

    if (tt.pointers != ft.pointers) {
        goto fail;
    }

    if (tt.is_array != ft.is_array) {
        goto fail;
    }

    if (tt.is_array && tt.array_size != ft.array_size) {
        goto fail;
    }

    if (tt.calling_convention != ft.calling_convention) {
        goto fail;
    }

    lua_pushboolean(L, 1);
    return 1;

fail:
    lua_pushboolean(L, 0);
    return 1;
}

static int cdata_gc(lua_State* L) {
    struct ctype ct;
    check_cdata(L, 1, &ct);
    lua_settop(L, 1);

    /* call the gc func if there is any registered */
    lua_pushvalue(L, 1);
    lua_rawget(L, lua_upvalueindex(1));
    if (!lua_isnil(L, -1)) {
        lua_pushvalue(L, 1);
        lua_pcall(L, 1, 0, 0);
    }

    /* unset the closure */
    lua_pushvalue(L, 1);
    lua_pushnil(L);
    lua_rawset(L, lua_upvalueindex(1));

    return 0;
}

static int user_mt_key;

static int ffi_metatype(lua_State* L) {
    struct ctype ct;
    lua_settop(L, 2);

    check_ctype(L, 1, &ct);
    if (lua_type(L, 2) != LUA_TTABLE && lua_type(L, 2) != LUA_TNIL) {
        return luaL_argerror(L, 2, "metatable must be a table or nil");
    }

    lua_pushlightuserdata(L, &user_mt_key);
    lua_pushvalue(L, 2);
    lua_rawset(L, 3); /* user[user_mt_key] = mt */

    /* return the passed in ctype */
    push_ctype(L, 3, &ct);
    return 1;
}

/* push_user_mt returns 1 if the type has a user metatable and pushes it onto
 * the stack, otherwise it returns 0 and pushes nothing */
int push_user_mt(lua_State* L, int ct_usr, const struct ctype* ct) {
    if (ct->type != STRUCT_TYPE && ct->type != UNION_TYPE) {
        return 0;
    }

    ct_usr = lua_absindex(L, ct_usr);
    lua_pushlightuserdata(L, &user_mt_key);
    lua_rawget(L, ct_usr);

    if (lua_isnil(L, -1)) {
        lua_pop(L, 1);
        return 0;
    }
    return 1;
}

static int ffi_gc(lua_State* L) {
    struct ctype ct;
    lua_settop(L, 2);
    check_cdata(L, 1, &ct);

    push_upval(L, &gc_key);
    lua_pushvalue(L, 1);
    lua_pushvalue(L, 2);
    lua_rawset(L, -3);

    /* return the cdata back */
    lua_settop(L, 1);
    return 1;
}

/* lookup_cdata_index returns the offset of the found type and user value on
 * the stack if valid. Otherwise returns -ve and doesn't touch the stack.
 */
static ptrdiff_t lookup_cdata_index(lua_State* L, int idx, int ct_usr, struct ctype* ct) {
    struct ctype mt;
    ptrdiff_t off;

    ct_usr = lua_absindex(L, ct_usr);

    switch (lua_type(L, idx)) {
        case LUA_TNUMBER:
            /* possibilities are array, pointer */

            if (!ct->pointers || is_void_ptr(ct)) {
                return -1;
            }

            ct->is_array = 0;
            ct->pointers--;
            ct->const_mask >>= 1;

            lua_pushvalue(L, ct_usr);

            return (ct->pointers ? sizeof(void*) : ct->base_size) * lua_tonumber(L, 2);

        case LUA_TSTRING:
            /* possibilities are struct/union, pointer to struct/union */

            if ((ct->type != STRUCT_TYPE && ct->type != UNION_TYPE) || ct->is_array ||
                ct->pointers > 1) {
                return -1;
            }

            lua_pushvalue(L, idx);
            off = get_member(L, ct_usr, ct, &mt);
            if (off < 0) {
                return -1;
            }

            *ct = mt;
            return off;

        default:
            return -1;
    }
}

static int cdata_newindex(lua_State* L) {
    struct ctype tt;
    char* to;
    ptrdiff_t off;

    lua_settop(L, 3);

    to = (char*)check_cdata(L, 1, &tt);
    off = lookup_cdata_index(L, 2, -1, &tt);

    if (off < 0) {
        if (!push_user_mt(L, -1, &tt)) {
            goto err;
        }

        lua_pushliteral(L, "__newindex");
        lua_rawget(L, -2);

        if (lua_isnil(L, -1)) {
            goto err;
        }

        lua_insert(L, 1);
        lua_settop(L, 4);
        lua_call(L, 3, LUA_MULTRET);
        return lua_gettop(L);
    }

    if (tt.const_mask & 1) {
        return luaL_error(L, "can't set const data");
    }

    set_value(L, 3, to + off, -1, &tt, 1);
    return 0;

err:
    push_type_name(L, 4, &tt);
    return luaL_error(L, "type %s has no member %s", lua_tostring(L, -1),
                      lua_tostring(L, 2));
}

static int cdata_index(lua_State* L) {
    void* to;
    struct ctype ct;
    char* data;
    ptrdiff_t off;

    lua_settop(L, 2);
    data = (char*)check_cdata(L, 1, &ct);
    assert(lua_gettop(L) == 3);

    if (!ct.pointers) {
        switch (ct.type) {
            case FUNCTION_PTR_TYPE:
                /* Callbacks use the same metatable as standard cdata values, but have set
                 * and free members. So instead of mt.__index = mt, we do the equiv here.
                 */
                lua_getmetatable(L, 1);
                lua_pushvalue(L, 2);
                lua_rawget(L, -2);
                return 1;

                /* This provides the .re and .im virtual members */
            case COMPLEX_DOUBLE_TYPE:
            case COMPLEX_FLOAT_TYPE:
                if (!lua_isstring(L, 2)) {
                    luaL_error(L, "invalid member for complex number");

                } else if (strcmp(lua_tostring(L, 2), "re") == 0) {
                    lua_pushnumber(L, ct.type == COMPLEX_DOUBLE_TYPE
                                              ? creal(*(complex_double*)data)
                                              : crealf(*(complex_float*)data));

                } else if (strcmp(lua_tostring(L, 2), "im") == 0) {
                    lua_pushnumber(L, ct.type == COMPLEX_DOUBLE_TYPE
                                              ? cimag(*(complex_double*)data)
                                              : cimagf(*(complex_float*)data));

                } else {
                    luaL_error(L, "invalid member for complex number");
                }
                return 1;
        }
    }

    off = lookup_cdata_index(L, 2, -1, &ct);

    if (off < 0) {
        assert(lua_gettop(L) == 3);
        if (!push_user_mt(L, -1, &ct)) {
            goto err;
        }

        lua_pushliteral(L, "__index");
        lua_rawget(L, -2);

        if (lua_isnil(L, -1)) {
            goto err;
        }

        if (lua_istable(L, -1)) {
            lua_pushvalue(L, 2);
            lua_gettable(L, -2);
            return 1;
        }

        lua_insert(L, 1);
        lua_settop(L, 3);
        lua_call(L, 2, LUA_MULTRET);
        return lua_gettop(L);

    err:
        push_type_name(L, 3, &ct);
        return luaL_error(L, "type %s has no member %s", lua_tostring(L, -1),
                          lua_tostring(L, 2));
    }

    assert(lua_gettop(L) == 4); /* ct, key, ct_usr, mbr_usr */
    data += off;

    if (ct.is_array) {
        /* push a reference to the array */
        ct.is_reference = 1;
        to = push_cdata(L, -1, &ct);
        *(void**)to = data;
        return 1;

    } else if (ct.is_bitfield) {
        if (ct.type == INT64_TYPE) {
            struct ctype rt;
            uint64_t val = *(uint64_t*)data;
            val >>= ct.bit_offset;
            val &= (UINT64_C(1) << ct.bit_size) - 1;

            memset(&rt, 0, sizeof(rt));
            rt.base_size = 8;
            rt.type = INT64_TYPE;
            rt.is_unsigned = 1;
            rt.is_defined = 1;

            to = push_cdata(L, 0, &rt);
            *(uint64_t*)to = val;

            return 1;

        } else if (ct.type == BOOL_TYPE) {
            uint64_t val = *(uint64_t*)data;
            lua_pushboolean(L, (int)(val & (UINT64_C(1) << ct.bit_offset)));
            return 1;

        } else {
            uint64_t val = *(uint64_t*)data;
            val >>= ct.bit_offset;
            val &= (UINT64_C(1) << ct.bit_size) - 1;
            lua_pushnumber(L, val);
            return 1;
        }

    } else if (ct.pointers) {
#ifndef ALLOW_MISALIGNED_ACCESS
        union {
            uint8_t c[8];
            void* p;
        } misalignbuf;

        if ((uintptr_t)data & PTR_ALIGN_MASK) {
            memcpy(misalignbuf.c, data, sizeof(void*));
            data = misalignbuf.c;
        }
#endif
        to = push_cdata(L, -1, &ct);
        *(void**)to = *(void**)data;
        return 1;

    } else if (ct.type == STRUCT_TYPE || ct.type == UNION_TYPE) {
        /* push a reference to the member */
        ct.is_reference = 1;
        to = push_cdata(L, -1, &ct);
        *(void**)to = data;
        return 1;

    } else if (ct.type == FUNCTION_PTR_TYPE) {
        cfunction* pf = (cfunction*)push_cdata(L, -1, &ct);
        *pf = *(cfunction*)data;
        return 1;

    } else {
#ifndef ALLOW_MISALIGNED_ACCESS
        union {
            uint8_t c[8];
            double d;
            float f;
            uint64_t u64;
        } misalignbuf;

        assert(ct.base_size <= 8);

        if ((uintptr_t)data & (ct.base_size - 1)) {
            memcpy(misalignbuf.c, data, ct.base_size);
            data = misalignbuf.c;
        }
#endif

        switch (ct.type) {
            case BOOL_TYPE:
                lua_pushboolean(L, *(_Bool*)data);
                break;
            case INT8_TYPE:
                lua_pushnumber(L, ct.is_unsigned ? (lua_Number) * (uint8_t*)data
                                                 : (lua_Number) * (int8_t*)data);
                break;
            case INT16_TYPE:
                lua_pushnumber(L, ct.is_unsigned ? (lua_Number) * (uint16_t*)data
                                                 : (lua_Number) * (int16_t*)data);
                break;
            case ENUM_TYPE:
            case INT32_TYPE:
                lua_pushnumber(L, ct.is_unsigned ? (lua_Number) * (uint32_t*)data
                                                 : (lua_Number) * (int32_t*)data);
                break;
            case INT64_TYPE:
                to = push_cdata(L, -1, &ct);
                *(int64_t*)to = *(int64_t*)data;
                break;
            case INTPTR_TYPE:
                to = push_cdata(L, -1, &ct);
                *(intptr_t*)to = *(intptr_t*)data;
                break;
            case FLOAT_TYPE:
                lua_pushnumber(L, *(float*)data);
                break;
            case DOUBLE_TYPE:
                lua_pushnumber(L, *(double*)data);
                break;
            default:
                luaL_error(L, "internal error: invalid member type");
        }

        return 1;
    }
}

static complex_double check_complex(lua_State* L, int idx, void* p, struct ctype* ct) {
    if (ct->type == INVALID_TYPE) {
        double d = luaL_checknumber(L, idx);
#ifdef HAVE_COMPLEX
        return d;
#else
        complex_double c;
        c.real = d;
        c.imag = 0;
        return c;
#endif
    } else if (ct->type == COMPLEX_DOUBLE_TYPE) {
        return *(complex_double*)p;
    } else if (ct->type == COMPLEX_FLOAT_TYPE) {
        complex_float* f = (complex_float*)p;
#ifdef HAVE_COMPLEX
        return *f;
#else
        complex_double d;
        d.real = f->real;
        d.imag = f->imag;
        return d;
#endif
    } else {
        complex_double dummy;
        type_error(L, idx, "complex", 0, NULL);
        memset(&dummy, 0, sizeof(dummy));
        return dummy;
    }
}

static int rank(const struct ctype* ct) {
    if (ct->pointers) {
        return 5;
    }

    switch (ct->type) {
        case COMPLEX_DOUBLE_TYPE:
            return 7;
        case COMPLEX_FLOAT_TYPE:
            return 6;
        case INTPTR_TYPE:
            return sizeof(intptr_t) >= sizeof(int64_t) ? 4 : 1;
        case INT64_TYPE:
            return ct->is_unsigned ? 3 : 2;
        case INT32_TYPE:
        case INT16_TYPE:
        case INT8_TYPE:
            return 2;
        default:
            return 0;
    }
}

static void push_complex(lua_State* L, complex_double res, int ct_usr,
                         const struct ctype* ct) {
    if (ct->type == COMPLEX_DOUBLE_TYPE) {
        complex_double* p = (complex_double*)push_cdata(L, ct_usr, ct);
        *p = res;
    } else {
        complex_float* p = (complex_float*)push_cdata(L, ct_usr, ct);
#ifdef HAVE_COMPLEX
        *p = (complex float)res;
#else
        p->real = (float)res.real;
        p->imag = (float)res.imag;
#endif
    }
}

static void push_number(lua_State* L, int64_t val, int ct_usr, const struct ctype* ct) {
    if ((ct->pointers || ct->type == INTPTR_TYPE) &&
        sizeof(intptr_t) != sizeof(int64_t)) {
        intptr_t* p = (intptr_t*)push_cdata(L, ct_usr, ct);
        *p = val;
    } else {
        int64_t* p = (int64_t*)push_cdata(L, ct_usr, ct);
        *p = val;
    }
}

static int call_user_op(lua_State* L, const char* opfield, int idx, int ct_usr,
                        const struct ctype* ct) {
    idx = lua_absindex(L, idx);

    if (push_user_mt(L, ct_usr, ct)) {
        lua_pushstring(L, opfield);
        lua_rawget(L, -2);
        if (!lua_isnil(L, -1)) {
            int top = lua_gettop(L);
            lua_pushvalue(L, idx);
            lua_call(L, 1, LUA_MULTRET);
            return lua_gettop(L) - top + 1;
        }
        lua_pop(L, 2);
    }
    return -1;
}

static int cdata_unm(lua_State* L) {
    struct ctype ct;
    void* p;
    int64_t val;
    int ret;

    lua_settop(L, 1);
    p = to_cdata(L, 1, &ct);

    ret = call_user_op(L, "__unm", 1, 2, &ct);
    if (ret >= 0) {
        return ret;
    }

    val = check_intptr(L, 1, p, &ct);

    if (ct.pointers) {
        luaL_error(L, "can't negate a pointer value");
    } else {
        memset(&ct, 0, sizeof(ct));
        ct.type = INT64_TYPE;
        ct.base_size = 8;
        ct.is_defined = 1;
        push_number(L, -val, 0, &ct);
    }

    return 1;
}

/* returns -ve if no binop was called otherwise returns the number of return
 * arguments */
static int call_user_binop(lua_State* L, const char* opfield, int lidx, int lusr,
                           const struct ctype* lt, int ridx, int rusr,
                           const struct ctype* rt) {
    lidx = lua_absindex(L, lidx);
    ridx = lua_absindex(L, ridx);

    if (push_user_mt(L, lusr, lt)) {
        lua_pushstring(L, opfield);
        lua_rawget(L, -2);

        if (!lua_isnil(L, -1)) {
            int top = lua_gettop(L);
            lua_pushvalue(L, lidx);
            lua_pushvalue(L, ridx);
            lua_call(L, 2, LUA_MULTRET);
            return lua_gettop(L) - top + 1;
        }

        lua_pop(L, 2); /* user_mt and user_mt.op */
    }

    if (push_user_mt(L, rusr, rt)) {
        lua_pushstring(L, opfield);
        lua_rawget(L, -2);

        if (!lua_isnil(L, -1)) {
            int top = lua_gettop(L);
            lua_pushvalue(L, lidx);
            lua_pushvalue(L, ridx);
            lua_call(L, 2, LUA_MULTRET);
            return lua_gettop(L) - top + 1;
        }

        lua_pop(L, 2); /* user_mt and user_mt.op */
    }

    return -1;
}

static int cdata_concat(lua_State* L) {
    struct ctype lt, rt;
    int ret;

    lua_settop(L, 2);
    to_cdata(L, 1, &lt);
    to_cdata(L, 2, &rt);

    ret = call_user_binop(L, "__concat", 1, 3, &lt, 2, 4, &rt);
    if (ret >= 0) {
        return ret;
    }

    return luaL_error(L, "NYI");
}

static int cdata_len(lua_State* L) {
    struct ctype ct;
    int ret;

    lua_settop(L, 1);
    to_cdata(L, 1, &ct);

    ret = call_user_op(L, "__len", 1, 2, &ct);
    if (ret >= 0) {
        return ret;
    }

    push_type_name(L, 2, &ct);
    return luaL_error(L, "type %s does not implement the __len metamethod",
                      lua_tostring(L, -1));
}

static int cdata_pairs(lua_State* L) {
    struct ctype ct;
    int ret;

    lua_settop(L, 1);
    to_cdata(L, 1, &ct);

    ret = call_user_op(L, "__pairs", 1, 2, &ct);
    if (ret >= 0) {
        return ret;
    }

    push_type_name(L, 2, &ct);
    return luaL_error(L, "type %s does not implement the __pairs metamethod",
                      lua_tostring(L, -1));
}

static int cdata_ipairs(lua_State* L) {
    struct ctype ct;
    int ret;

    lua_settop(L, 1);
    to_cdata(L, 1, &ct);

    ret = call_user_op(L, "__ipairs", 1, 2, &ct);
    if (ret >= 0) {
        return ret;
    }

    push_type_name(L, 2, &ct);
    return luaL_error(L, "type %s does not implement the __ipairs metamethod",
                      lua_tostring(L, -1));
}

static int cdata_add(lua_State* L) {
    struct ctype lt, rt, ct;
    void *lp, *rp;
    int ct_usr;
    int ret;

    lua_settop(L, 2);

    lp = to_cdata(L, 1, &lt);
    rp = to_cdata(L, 2, &rt);
    assert(lua_gettop(L) == 4);

    ret = call_user_binop(L, "__add", 1, 3, &lt, 2, 4, &rt);
    if (ret >= 0) {
        return ret;
    }
    assert(lua_gettop(L) == 4);

    ct_usr = rank(&lt) > rank(&rt) ? 3 : 4;
    ct = rank(&lt) > rank(&rt) ? lt : rt;

    if (IS_COMPLEX(ct.type)) {
        complex_double left, right, res;

        left = check_complex(L, 1, lp, &lt);
        right = check_complex(L, 2, rp, &rt);
        assert(lua_gettop(L) == 4);

#ifdef HAVE_COMPLEX
        res = left + right;
#else
        res.real = left.real + right.real;
        res.imag = left.imag + right.imag;
#endif

        push_complex(L, res, ct_usr, &ct);
        return 1;

    } else {
        int64_t left = check_intptr(L, 1, lp, &lt);
        int64_t right = check_intptr(L, 2, rp, &rt);
        assert(lua_gettop(L) == 4);

        /* note due to 2s complement it doesn't matter if we do the addition as int or
         * uint, but the result needs to be uint64_t if either of the sources are */

        if (lt.pointers && rt.pointers) {
            luaL_error(L, "can't add two pointers");

        } else if (lt.pointers) {
            int64_t res = left + (lt.pointers > 1 ? sizeof(void*) : lt.base_size) * right;
            lt.is_array = 0;
            push_number(L, res, 3, &lt);

        } else if (rt.pointers) {
            int64_t res = right + (rt.pointers > 1 ? sizeof(void*) : rt.base_size) * left;
            rt.is_array = 0;
            push_number(L, res, 4, &rt);

        } else {
            push_number(L, left + right, ct_usr, &ct);
        }

        return 1;
    }
}

static int cdata_sub(lua_State* L) {
    struct ctype lt, rt, ct;
    void *lp, *rp;
    int ct_usr;
    int ret;

    lua_settop(L, 2);

    lp = to_cdata(L, 1, &lt);
    rp = to_cdata(L, 2, &rt);

    ret = call_user_binop(L, "__sub", 1, 3, &lt, 2, 4, &rt);
    if (ret >= 0) {
        return ret;
    }

    ct_usr = rank(&lt) > rank(&rt) ? 3 : 4;
    ct = rank(&lt) > rank(&rt) ? lt : rt;

    if (IS_COMPLEX(ct.type)) {
        complex_double left, right, res;

        left = check_complex(L, 1, lp, &lt);
        right = check_complex(L, 2, rp, &rt);

#ifdef HAVE_COMPLEX
        res = left - right;
#else
        res.real = left.real - right.real;
        res.imag = left.imag - right.imag;
#endif

        push_complex(L, res, ct_usr, &ct);
        return 1;

    } else {
        int64_t left = check_intptr(L, 1, lp, &lt);
        int64_t right = check_intptr(L, 2, rp, &rt);

        if (rt.pointers) {
            luaL_error(L, "NYI: can't subtract a pointer value");

        } else if (lt.pointers) {
            int64_t res = left - (lt.pointers > 1 ? sizeof(void*) : lt.base_size) * right;
            lt.is_array = 0;
            push_number(L, res, 3, &lt);

        } else {
            int64_t res = left - right;
            push_number(L, res, ct_usr, &ct);
        }

        return 1;
    }
}

/* TODO fix for unsigned */
#define NUMBER_ONLY_BINOP(OPSTR, DO_NORMAL, DO_COMPLEX)      \
    struct ctype lt, rt, ct;                                 \
    void *lp, *rp;                                           \
    int ct_usr;                                              \
    int ret;                                                 \
                                                             \
    lua_settop(L, 2);                                        \
                                                             \
    lp = to_cdata(L, 1, &lt);                                \
    rp = to_cdata(L, 2, &rt);                                \
                                                             \
    ret = call_user_binop(L, OPSTR, 1, 3, &lt, 2, 4, &rt);   \
    if (ret >= 0) {                                          \
        return ret;                                          \
    }                                                        \
                                                             \
    ct_usr = rank(&lt) > rank(&rt) ? 3 : 4;                  \
    ct = rank(&lt) > rank(&rt) ? lt : rt;                    \
                                                             \
    if (IS_COMPLEX(ct.type)) {                               \
        complex_double res;                                  \
        complex_double left = check_complex(L, 1, lp, &lt);  \
        complex_double right = check_complex(L, 2, rp, &rt); \
                                                             \
        DO_COMPLEX(left, right, res);                        \
        push_complex(L, res, ct_usr, &ct);                   \
                                                             \
    } else if (lt.pointers || rt.pointers) {                 \
        luaL_error(L, "can't operate on a pointer value");   \
                                                             \
    } else {                                                 \
        int64_t res;                                         \
        int64_t left = check_intptr(L, 1, lp, &lt);          \
        int64_t right = check_intptr(L, 2, rp, &rt);         \
                                                             \
        DO_NORMAL(left, right, res);                         \
        push_number(L, res, ct_usr, &ct);                    \
    }                                                        \
                                                             \
    return 1

#define MUL(l, r, s) s = l * r
#define DIV(l, r, s) s = l / r
#define MOD(l, r, s) s = l % r
#define POW(l, r, s) s = pow(l, r)

#ifdef HAVE_COMPLEX
#define MULC(l, r, s) s = l * r
#define DIVC(l, r, s) s = l / r
#define MODC(l, r, s) \
    (void)l, (void)r, memset(&s, 0, sizeof(s)), luaL_error(L, "NYI: complex mod")
#define POWC(l, r, s) s = cpow(l, r)
#else
#define MULC(l, r, s) \
    s.real = l.real * r.real - l.imag * r.imag, s.imag = l.real * r.imag + l.imag * r.real
#define DIVC(l, r, s)                                                                   \
    s.real = (l.real * r.real + l.imag * r.imag) / (r.real * r.real + r.imag * r.imag), \
    s.imag = (l.imag * r.real - l.real * r.imag) / (r.real * r.real + r.imag * r.imag)
#define MODC(l, r, s) \
    (void)l, (void)r, memset(&s, 0, sizeof(s)), luaL_error(L, "NYI: complex mod")
#define POWC(l, r, s) \
    (void)l, (void)r, memset(&s, 0, sizeof(s)), luaL_error(L, "NYI: complex pow")
#endif

static int cdata_mul(lua_State* L) { NUMBER_ONLY_BINOP("__mul", MUL, MULC); }

static int cdata_div(lua_State* L) { NUMBER_ONLY_BINOP("__div", DIV, DIVC); }

static int cdata_mod(lua_State* L) { NUMBER_ONLY_BINOP("__mod", MOD, MODC); }

static int cdata_pow(lua_State* L) { NUMBER_ONLY_BINOP("__pow", POW, POWC); }

#define COMPARE_BINOP(OPSTR, OP, OPC)                                         \
    struct ctype lt, rt;                                                      \
    void *lp, *rp;                                                            \
    int ret, res;                                                             \
                                                                              \
    lua_settop(L, 2);                                                         \
                                                                              \
    lp = to_cdata(L, 1, &lt);                                                 \
    rp = to_cdata(L, 2, &rt);                                                 \
                                                                              \
    ret = call_user_binop(L, OPSTR, 1, 3, &lt, 2, 4, &rt);                    \
    if (ret >= 0) {                                                           \
        return ret;                                                           \
    }                                                                         \
                                                                              \
    if (IS_COMPLEX(lt.type) || IS_COMPLEX(rt.type)) {                         \
        complex_double left = check_complex(L, 1, lp, &lt);                   \
        complex_double right = check_complex(L, 2, rp, &rt);                  \
                                                                              \
        res = OPC(left, right);                                               \
                                                                              \
        lua_pushboolean(L, res);                                              \
                                                                              \
    } else {                                                                  \
        int64_t left = check_intptr(L, 1, lp, &lt);                           \
        int64_t right = check_intptr(L, 2, rp, &rt);                          \
                                                                              \
        if (lt.pointers && rt.pointers) {                                     \
            if (is_void_ptr(&lt) || is_void_ptr(&rt) ||                       \
                is_same_type(L, 3, 4, &lt, &rt)) {                            \
                res = OP((uint64_t)left, (uint64_t)right);                    \
            } else {                                                          \
                goto err;                                                     \
            }                                                                 \
                                                                              \
        } else if (lt.is_null && rt.type == FUNCTION_PTR_TYPE) {              \
            res = OP((uint64_t)left, (uint64_t)right);                        \
                                                                              \
        } else if (rt.is_null && lt.type == FUNCTION_PTR_TYPE) {              \
            res = OP((uint64_t)left, (uint64_t)right);                        \
                                                                              \
        } else if (lt.pointers && rt.type == INTPTR_TYPE && rt.is_unsigned) { \
            res = OP((uint64_t)left, (uint64_t)right);                        \
                                                                              \
        } else if (rt.pointers && lt.type == INTPTR_TYPE && lt.is_unsigned) { \
            res = OP((uint64_t)left, (uint64_t)right);                        \
                                                                              \
        } else if (rt.pointers || lt.pointers) {                              \
            goto err;                                                         \
                                                                              \
        } else if (lt.is_unsigned && rt.is_unsigned) {                        \
            res = OP((uint64_t)left, (uint64_t)right);                        \
                                                                              \
        } else if (lt.is_unsigned) {                                          \
            res = OP((int64_t)(uint64_t)left, right);                         \
                                                                              \
        } else if (rt.is_unsigned) {                                          \
            res = OP(left, (int64_t)(uint64_t)right);                         \
                                                                              \
        } else {                                                              \
            res = OP(left, right);                                            \
        }                                                                     \
                                                                              \
        lua_pushboolean(L, res);                                              \
    }                                                                         \
    return 1

#define EQ(l, r) (l) == (r)
#define LT(l, r) (l) < (r)
#define LE(l, r) (l) <= (r)

#ifdef HAVE_COMPLEX
#define EQC(l, r) (l) == (r)
#else
#define EQC(l, r) (l).real == (r).real && (l).imag == (r).imag
#endif

#define LEC(l, r) EQC(l, r), luaL_error(L, "complex numbers are non-orderable")
#define LTC(l, r) EQC(l, r), luaL_error(L, "complex numbers are non-orderable")

static int cdata_eq(lua_State* L) {
    COMPARE_BINOP("__eq", EQ, EQC);
err:
    lua_pushboolean(L, 0);
    return 1;
}

static int cdata_lt(lua_State* L) {
    COMPARE_BINOP("__lt", LT, LTC);
err:
    lua_getuservalue(L, 1);
    lua_getuservalue(L, 2);
    push_type_name(L, -2, &lt);
    push_type_name(L, -2, &lt);
    return luaL_error(L, "trying to compare incompatible types %s and %s",
                      lua_tostring(L, -2), lua_tostring(L, -1));
}

static int cdata_le(lua_State* L) {
    COMPARE_BINOP("__le", LE, LEC);
err:
    lua_getuservalue(L, 1);
    lua_getuservalue(L, 2);
    push_type_name(L, -2, &lt);
    push_type_name(L, -2, &lt);
    return luaL_error(L, "trying to compare incompatible types %s and %s",
                      lua_tostring(L, -2), lua_tostring(L, -1));
}

static const char* etype_tostring(int type) {
    switch (type) {
        case VOID_TYPE:
            return "void";
        case DOUBLE_TYPE:
            return "double";
        case FLOAT_TYPE:
            return "float";
        case COMPLEX_DOUBLE_TYPE:
            return "complex double";
        case COMPLEX_FLOAT_TYPE:
            return "complex float";
        case BOOL_TYPE:
            return "bool";
        case INT8_TYPE:
            return "int8";
        case INT16_TYPE:
            return "int16";
        case INT32_TYPE:
            return "int32";
        case INT64_TYPE:
            return "int64";
        case INTPTR_TYPE:
            return "intptr";
        case ENUM_TYPE:
            return "enum";
        case UNION_TYPE:
            return "union";
        case STRUCT_TYPE:
            return "struct";
        case FUNCTION_PTR_TYPE:
            return "function ptr";
        case FUNCTION_TYPE:
            return "function";
        default:
            return "invalid";
    }
}

static void print_type(lua_State* L, const struct ctype* ct) {
    lua_pushfstring(L,
                    " sz %d %d %d align %d ptr %d %d %d type %s%s %d %d %d name %d call "
                    "%d %d var %d %d %d bit %d %d %d %d",
                    /* sz */
                    ct->base_size, ct->array_size, ct->offset,
                    /* align */
                    ct->align_mask,
                    /* ptr */
                    ct->is_array, ct->pointers, ct->const_mask,
                    /* type */
                    ct->is_unsigned ? "u" : "", etype_tostring(ct->type),
                    ct->is_reference, ct->is_defined, ct->is_null,
                    /* name */
                    ct->has_member_name,
                    /* call */
                    ct->calling_convention, ct->has_var_arg,
                    /* var */
                    ct->is_variable_array, ct->is_variable_struct,
                    ct->variable_size_known,
                    /* bit */
                    ct->is_bitfield, ct->has_bitfield, ct->bit_offset, ct->bit_size);
}

static int ctype_tostring(lua_State* L) {
    struct ctype ct;
    assert(lua_type(L, 1) == LUA_TUSERDATA);
    lua_settop(L, 1);
    check_ctype(L, 1, &ct);
    assert(lua_gettop(L) == 2);
    push_type_name(L, -1, &ct);
    lua_pushfstring(L, "%s", lua_tostring(L, -1));

    if (DEBUG_TOSTRING) {
        print_type(L, &ct);
        lua_concat(L, 2);
    }

    return 1;
}

static int cdata_tostring(lua_State* L) {
    struct ctype ct;
    char buf[64];
    void* p;
    int ret;

    lua_settop(L, 1);
    p = to_cdata(L, 1, &ct);

    ret = call_user_op(L, "__tostring", 1, 2, &ct);
    if (ret >= 0) {
        return ret;
    }

    if (ct.pointers > 0 || ct.type == STRUCT_TYPE || ct.type == UNION_TYPE) {
        push_type_name(L, -1, &ct);
        lua_pushfstring(L, "cdata<%s>: %p", lua_tostring(L, -1), p);

        if (DEBUG_TOSTRING) {
            print_type(L, &ct);
            lua_concat(L, 2);
        }

        return 1;
    }

    switch (ct.type) {
        case COMPLEX_DOUBLE_TYPE: {
            complex_double c = *(complex_double*)p;
            if (cimag(c) != 0) {
                lua_pushfstring(L, "%f+%fi", creal(c), cimag(c));
            } else {
                lua_pushfstring(L, "%f", creal(c));
            }
        }
            return 1;

        case COMPLEX_FLOAT_TYPE: {
            complex_float c = *(complex_float*)p;
            if (cimagf(c) != 0) {
                lua_pushfstring(L, "%f+%fi", crealf(c), cimagf(c));
            } else {
                lua_pushfstring(L, "%f", crealf(c));
            }
        }
            return 1;

        case FUNCTION_PTR_TYPE:
            p = *(void**)p;
            push_type_name(L, -1, &ct);
            lua_pushfstring(L, "cdata<%s>: %p", lua_tostring(L, -1), *(void**)p);
            return 1;

        case INTPTR_TYPE:
            lua_pushfstring(L, "%p", *(uintptr_t*)p);
            return 1;

        case INT64_TYPE:
            sprintf(buf, ct.is_unsigned ? "%" PRIu64 : "%" PRId64, *(uint64_t*)p);
            lua_pushstring(L, buf);
            return 1;

        default:
            sprintf(buf, ct.is_unsigned ? "%" PRId64 : "%" PRId64,
                    (int64_t)check_intptr(L, 1, p, &ct));
            lua_pushstring(L, buf);
            return 1;
    }
}

static int ffi_number(lua_State* L) {
    struct ctype ct;
    void* data = to_cdata(L, 1, &ct);

    if (ct.type != INVALID_TYPE) {
        lua_pushnumber(L, check_intptr(L, 1, data, &ct));
        return 1;
    } else {
        /* call the old _G.tonumber, we use an upvalue as _G.tonumber is set
         * to this function */
        lua_pushvalue(L, lua_upvalueindex(1));
        lua_insert(L, 1);
        lua_call(L, lua_gettop(L) - 1, LUA_MULTRET);
        return lua_gettop(L);
    }
}

static int ffi_string(lua_State* L) {
    struct ctype ct;
    char* data;
    lua_settop(L, 2);

    data = (char*)check_cdata(L, 1, &ct);

    if (is_void_ptr(&ct)) {
        lua_pushlstring(L, data, (size_t)luaL_checknumber(L, 2));
        return 1;

    } else if (ct.type == INT8_TYPE && ct.pointers == 1) {
        size_t sz;

        if (!lua_isnil(L, 2)) {
            sz = (size_t)luaL_checknumber(L, 2);

        } else if (ct.is_array && !ct.is_variable_array) {
            char* nul = memchr(data, '\0', ct.array_size);
            sz = nul ? nul - data : ct.array_size;

        } else {
            sz = strlen(data);
        }

        lua_pushlstring(L, data, sz);
        return 1;
    }

    return luaL_error(L, "unable to convert cdata to string");
}

static int ffi_copy(lua_State* L) {
    struct ctype ft, tt;
    char *to, *from;

    setmintop(L, 3);
    to = (char*)check_pointer(L, 1, &tt);
    from = (char*)check_pointer(L, 2, &ft);

    if (!lua_isnoneornil(L, 3)) {
        memcpy(to, from, (size_t)luaL_checknumber(L, 3));

    } else if (ft.type == INT8_TYPE && ft.pointers == 1) {
        size_t sz = ft.is_array ? ft.array_size : strlen(from);
        memcpy(to, from, sz);
        to[sz] = '\0';
    }

    return 0;
}

static int ffi_fill(lua_State* L) {
    struct ctype ct;
    void* to;
    size_t sz;
    int val = 0;

    setmintop(L, 3);
    to = check_pointer(L, 1, &ct);
    sz = (size_t)luaL_checknumber(L, 2);

    if (!lua_isnoneornil(L, 3)) {
        val = (int)luaL_checkinteger(L, 3);
    }

    memset(to, val, sz);
    return 0;
}

static int ffi_abi(lua_State* L) {
    luaL_checkstring(L, 1);
    push_upval(L, &abi_key);
    lua_pushvalue(L, 1);
    lua_rawget(L, -2);
    lua_pushboolean(L, lua_toboolean(L, -1));
    return 1;
}

static int ffi_load(lua_State* L) {
    const char* libname = luaL_checkstring(L, 1);
    void** lib = (void**)lua_newuserdata(L, sizeof(void*));

    *lib = LoadLibraryA(libname);

#ifdef LIB_FORMAT_1
    if (!*lib) {
        libname = lua_pushfstring(L, LIB_FORMAT_1, lua_tostring(L, 1));
        *lib = LoadLibraryA(libname);
        lua_pop(L, 1);
    }
#endif

#ifdef LIB_FORMAT_2
    if (!*lib) {
        libname = lua_pushfstring(L, LIB_FORMAT_2, lua_tostring(L, 1));
        *lib = LoadLibraryA(libname);
        lua_pop(L, 1);
    }
#endif

    if (!*lib) {
        return luaL_error(L, "could not load library %s", lua_tostring(L, 1));
    }

    lua_newtable(L);
    lua_setuservalue(L, -2);

    push_upval(L, &cmodule_mt_key);
    lua_setmetatable(L, -2);
    return 1;
}

static void* find_symbol(lua_State* L, int modidx, const char* asmname) {
    size_t i;
    void** libs;
    size_t num;
    void* sym = NULL;

    libs = (void**)lua_touserdata(L, modidx);
    num = lua_rawlen(L, modidx) / sizeof(void*);

    for (i = 0; i < num && sym == NULL; i++) {
        if (libs[i]) {
            sym = GetProcAddressA(libs[i], asmname);
        }
    }

    return sym;
}

/* pushes the user table */
static void* lookup_global(lua_State* L, int modidx, int nameidx, const char** pname,
                           struct ctype* ct) {
    int top = lua_gettop(L);
    void* sym;

    modidx = lua_absindex(L, modidx);
    nameidx = lua_absindex(L, nameidx);

    *pname = luaL_checkstring(L, nameidx);

    /* get the ctype */
    push_upval(L, &functions_key);
    lua_pushvalue(L, nameidx);
    lua_rawget(L, -2);
    if (lua_isnil(L, -1)) {
        luaL_error(L, "missing declaration for function/global %s", *pname);
        return NULL;
    }

    /* leave just the ct_usr on the stack */
    *ct = *(const struct ctype*)lua_touserdata(L, -1);
    lua_getuservalue(L, -1);
    lua_replace(L, top + 1);
    lua_pop(L, 1);

    assert(lua_gettop(L) == top + 1);

    /* get the assembly name */
    push_upval(L, &asmname_key);
    lua_pushvalue(L, nameidx);
    lua_rawget(L, -2);
    if (lua_isstring(L, -1)) {
        *pname = lua_tostring(L, -1);
    }
    lua_pop(L, 2);

    sym = find_symbol(L, modidx, *pname);

    assert(lua_gettop(L) == top + 1);
    return sym;
}

static int cmodule_index(lua_State* L) {
    const char* asmname;
    struct ctype ct;
    void* sym;

    lua_settop(L, 2);

    /* see if we have already loaded the function */
    lua_getuservalue(L, 1);
    lua_pushvalue(L, 2);
    lua_rawget(L, -2);
    if (!lua_isnil(L, -1)) {
        return 1;
    }
    lua_pop(L, 2);

    /* check the constants table */
    push_upval(L, &constants_key);
    lua_pushvalue(L, 2);
    lua_rawget(L, -2);
    if (!lua_isnil(L, -1)) {
        return 1;
    }
    lua_pop(L, 2);

    /* lookup_global pushes the ct_usr */
    sym = lookup_global(L, 1, 2, &asmname, &ct);

#if defined _WIN32 && !defined _WIN64 && (defined __i386__ || defined _M_IX86)
    if (!sym && ct.type == FUNCTION_TYPE) {
        ct.calling_convention = STD_CALL;
        lua_pushfstring(L, "_%s@%d", asmname, x86_return_size(L, -1, &ct));
        sym = find_symbol(L, 1, lua_tostring(L, -1));
        lua_pop(L, 1);
    }

    if (!sym && ct.type == FUNCTION_TYPE) {
        ct.calling_convention = FAST_CALL;
        lua_pushfstring(L, "@%s@%d", asmname, x86_return_size(L, -1, &ct));
        sym = find_symbol(L, 1, lua_tostring(L, -1));
        lua_pop(L, 1);
    }
#endif

    if (!sym) {
        return luaL_error(L, "failed to find function/global %s", asmname);
    }

    assert(lua_gettop(L) == 3); /* module, name, ct_usr */

    if (ct.type == FUNCTION_TYPE) {
        assert(!"callbacks are unimplemented");
    }

    /* extern const char* foo; and extern const char foo[]; */
    if (ct.pointers == 1 && ct.type == INT8_TYPE) {
        char* str = (char*)sym;
        if (!ct.is_array) {
            str = *(char**)sym;
        }
        lua_pushstring(L, str);
        return 1;
    }

    /* extern struct foo foo[], extern void* foo[]; and extern struct foo foo; */
    if (ct.is_array ||
        (!ct.pointers && (ct.type == UNION_TYPE || ct.type == STRUCT_TYPE))) {
        void* p;
        ct.is_reference = 1;
        p = push_cdata(L, -1, &ct);
        *(void**)p = sym;
        return 1;
    }

    /* extern void* foo; and extern void (*foo)(); */
    if (ct.pointers || ct.type == FUNCTION_PTR_TYPE) {
        void* p = push_cdata(L, -1, &ct);
        *(void**)p = *(void**)sym;
        return 1;
    }

    switch (ct.type) {
        case COMPLEX_DOUBLE_TYPE:
        case COMPLEX_FLOAT_TYPE:
        case INTPTR_TYPE:
        case INT64_TYPE: {
            /* TODO: complex float/double need to be references if .re and
             * .imag are setable */
            void* p = push_cdata(L, -1, &ct);
            memcpy(p, sym, ct.base_size);
            return 1;
        }

        case DOUBLE_TYPE:
            lua_pushnumber(L, *(double*)sym);
            return 1;

        case FLOAT_TYPE:
            lua_pushnumber(L, *(float*)sym);
            return 1;

        case BOOL_TYPE:
            lua_pushboolean(L, *(bool*)sym);
            return 1;

        case INT8_TYPE:
            lua_pushnumber(L, ct.is_unsigned ? (lua_Number) * (uint8_t*)sym
                                             : (lua_Number) * (int8_t*)sym);
            return 1;

        case INT16_TYPE:
            lua_pushnumber(L, ct.is_unsigned ? (lua_Number) * (uint16_t*)sym
                                             : (lua_Number) * (int16_t*)sym);
            return 1;

        case INT32_TYPE:
        case ENUM_TYPE:
            lua_pushnumber(L, ct.is_unsigned ? (lua_Number) * (uint32_t*)sym
                                             : (lua_Number) * (int32_t*)sym);
            return 1;
    }

    return luaL_error(L, "NYI - global value type");
}

static int cmodule_newindex(lua_State* L) {
    const char* name;
    void* sym;
    struct ctype ct;

    lua_settop(L, 3);

    /* pushes the ct_usr */
    sym = lookup_global(L, 1, 2, &name, &ct);
    assert(lua_gettop(L) == 4); /* module, name, value, ct_usr */

    if (sym == NULL) {
        return luaL_error(L, "failed to find global %s", name);
    }

    if (ct.type == FUNCTION_TYPE || ct.is_array || (ct.const_mask & 1)) {
        return luaL_error(L, "can not set global %s", name);
    }

    set_value(L, 3, sym, -1, &ct, 1);
    return 0;
}

static const luaL_Reg cdata_mt[] = {{"__gc", &cdata_gc},
                                    {"__index", &cdata_index},
                                    {"__newindex", &cdata_newindex},
                                    {"__add", &cdata_add},
                                    {"__sub", &cdata_sub},
                                    {"__mul", &cdata_mul},
                                    {"__div", &cdata_div},
                                    {"__mod", &cdata_mod},
                                    {"__pow", &cdata_pow},
                                    {"__unm", &cdata_unm},
                                    {"__eq", &cdata_eq},
                                    {"__lt", &cdata_lt},
                                    {"__le", &cdata_le},
                                    {"__tostring", &cdata_tostring},
                                    {"__concat", &cdata_concat},
                                    {"__len", &cdata_len},
                                    {"__pairs", &cdata_pairs},
                                    {"__ipairs", &cdata_ipairs},
                                    {NULL, NULL}};

static const luaL_Reg ctype_mt[] = {{"__call", &ctype_call},
                                    {"__new", &ctype_new},
                                    {"__tostring", &ctype_tostring},
                                    {NULL, NULL}};

static const luaL_Reg cmodule_mt[] = {
        {"__index", &cmodule_index}, {"__newindex", &cmodule_newindex}, {NULL, NULL}};

static const luaL_Reg ffi_reg[] = {{"cdef", &ffi_cdef},       {"load", &ffi_load},
                                   {"new", &ffi_new},         {"typeof", &ffi_typeof},
                                   {"cast", &ffi_cast},       {"metatype", &ffi_metatype},
                                   {"gc", &ffi_gc},           {"sizeof", &ffi_sizeof},
                                   {"alignof", &ffi_alignof}, {"offsetof", &ffi_offsetof},
                                   {"istype", &ffi_istype},   {"string", &ffi_string},
                                   {"copy", &ffi_copy},       {"fill", &ffi_fill},
                                   {"abi", &ffi_abi},         {NULL, NULL}};

/* leaves the usr table on the stack */
static void push_builtin(lua_State* L, struct ctype* ct, const char* name, int type,
                         int size, int align, int is_unsigned) {
    memset(ct, 0, sizeof(*ct));
    ct->type = type;
    ct->base_size = size;
    ct->align_mask = align;
    ct->is_defined = 1;
    ct->is_unsigned = is_unsigned;

    push_upval(L, &types_key);
    push_ctype(L, 0, ct);
    lua_setfield(L, -2, name);
    lua_pop(L, 1); /* types */
}

static void add_typedef(lua_State* L, const char* from, const char* to) {
    struct ctype ct;
    struct parser P;
    P.line = 1;
    P.align_mask = DEFAULT_ALIGN_MASK;
    P.next = P.prev = from;

    push_upval(L, &types_key);
    parse_type(L, &P, &ct);
    parse_argument(L, &P, -1, &ct, NULL, NULL);
    push_ctype(L, -1, &ct);

    /* stack is at +4: types, type usr, arg usr, ctype */

    lua_setfield(L, -4, to);
    lua_pop(L, 3); /* types, type usr, arg usr */
}

static int setup_upvals(lua_State* L) {
    /* setup builtin types */
    {
        complex_double* pc;
        struct {
            char ch;
            uint16_t v;
        } a16;
        struct {
            char ch;
            uint32_t v;
        } a32;
        struct {
            char ch;
            uint64_t v;
        } a64;
        struct {
            char ch;
            float v;
        } af;
        struct {
            char ch;
            double v;
        } ad;
#ifdef HAVE_LONG_DOUBLE
        struct {
            char ch;
            long double v;
        } ald;
#endif
        struct {
            char ch;
            uintptr_t v;
        } aptr;
        struct ctype ct;
        struct {
            char ch;
            complex_float v;
        } cf;
        struct {
            char ch;
            complex_double v;
        } cd;
#if defined HAVE_LONG_DOUBLE && defined HAVE_COMPLEX
        struct {
            char ch;
            complex long double v;
        } cld;
#endif

        push_builtin(L, &ct, "void", VOID_TYPE, 0, 0, 0);
        push_builtin(L, &ct, "bool", BOOL_TYPE, sizeof(_Bool), sizeof(_Bool) - 1, 1);
        push_builtin(L, &ct, "uint8_t", INT8_TYPE, sizeof(uint8_t), 0, 1);
        push_builtin(L, &ct, "int8_t", INT8_TYPE, sizeof(int8_t), 0, 0);
        push_builtin(L, &ct, "uint16_t", INT16_TYPE, sizeof(uint16_t), ALIGNOF(a16), 1);
        push_builtin(L, &ct, "int16_t", INT16_TYPE, sizeof(int16_t), ALIGNOF(a16), 0);
        push_builtin(L, &ct, "uint32_t", INT32_TYPE, sizeof(uint32_t), ALIGNOF(a32), 1);
        push_builtin(L, &ct, "int32_t", INT32_TYPE, sizeof(int32_t), ALIGNOF(a32), 0);
        push_builtin(L, &ct, "uint64_t", INT64_TYPE, sizeof(uint64_t), ALIGNOF(a64), 1);
        push_builtin(L, &ct, "int64_t", INT64_TYPE, sizeof(int64_t), ALIGNOF(a64), 0);
        push_builtin(L, &ct, "float", FLOAT_TYPE, sizeof(float), ALIGNOF(af), 0);
        push_builtin(L, &ct, "double", DOUBLE_TYPE, sizeof(double), ALIGNOF(ad), 0);
#ifdef HAVE_LONG_DOUBLE
        push_builtin(L, &ct, "long double", LONG_DOUBLE_TYPE, sizeof(long double),
                     ALIGNOF(ald), 0);
#else
        push_builtin_undef(L, &ct, "long double", LONG_DOUBLE_TYPE);
#endif
        push_builtin(L, &ct, "uintptr_t", INTPTR_TYPE, sizeof(uintptr_t), ALIGNOF(aptr),
                     1);
        push_builtin(L, &ct, "intptr_t", INTPTR_TYPE, sizeof(uintptr_t), ALIGNOF(aptr),
                     0);
        push_builtin(L, &ct, "complex float", COMPLEX_FLOAT_TYPE, sizeof(complex_float),
                     ALIGNOF(cf), 0);
        push_builtin(L, &ct, "complex double", COMPLEX_DOUBLE_TYPE,
                     sizeof(complex_double), ALIGNOF(cd), 0);
#if defined HAVE_LONG_DOUBLE && defined HAVE_COMPLEX
        push_builtin(L, &ct, "complex long double", COMPLEX_LONG_DOUBLE_TYPE,
                     sizeof(complex long double), ALIGNOF(cld), 0);
#else
        push_builtin_undef(L, &ct, "complex long double", COMPLEX_LONG_DOUBLE_TYPE);
#endif

        /* add NULL and i constants */
        push_upval(L, &constants_key);

        memset(&ct, 0, sizeof(ct));
        ct.type = VOID_TYPE;
        ct.is_defined = 1;
        ct.pointers = 1;
        ct.is_null = 1;

        push_cdata(L, 0, &ct);
        lua_setfield(L, -2, "NULL");

        memset(&ct, 0, sizeof(ct));
        ct.type = COMPLEX_DOUBLE_TYPE;
        ct.is_defined = 1;
        ct.base_size = sizeof(complex_double);
        pc = (complex_double*)push_cdata(L, 0, &ct);
#ifdef HAVE_COMPLEX
        *pc = 1i;
#else
        pc->real = 0;
        pc->imag = 1;
#endif
        lua_setfield(L, -2, "i");

        lua_pop(L, 1); /* constants */
    }

    assert(lua_gettop(L) == 1);

    /* setup builtin typedefs */
    {
        add_typedef(L, "bool", "_Bool");

        if (sizeof(uint32_t) == sizeof(size_t)) {
            add_typedef(L, "uint32_t", "size_t");
            add_typedef(L, "int32_t", "ssize_t");
        } else if (sizeof(uint64_t) == sizeof(size_t)) {
            add_typedef(L, "uint64_t", "size_t");
            add_typedef(L, "int64_t", "ssize_t");
        }

        if (sizeof(int32_t) == sizeof(intptr_t)) {
            add_typedef(L, "int32_t", "intptr_t");
            add_typedef(L, "int32_t", "ptrdiff_t");
        } else if (sizeof(int64_t) == sizeof(intptr_t)) {
            add_typedef(L, "int64_t", "intptr_t");
            add_typedef(L, "int64_t", "ptrdiff_t");
        }

        if (sizeof(uint8_t) == sizeof(wchar_t)) {
            add_typedef(L, "uint8_t", "wchar_t");
        } else if (sizeof(uint16_t) == sizeof(wchar_t)) {
            add_typedef(L, "uint16_t", "wchar_t");
        } else if (sizeof(uint32_t) == sizeof(wchar_t)) {
            add_typedef(L, "uint32_t", "wchar_t");
        }

        if (sizeof(va_list) == sizeof(char*)) {
            add_typedef(L, "char*", "va_list");
        } else {
            struct {
                char ch;
                va_list v;
            } av;
            lua_pushfstring(L, "struct {char data[%d] __attribute__((align(%d)));}",
                            (int)sizeof(va_list), (int)ALIGNOF(av) + 1);
            add_typedef(L, lua_tostring(L, -1), "va_list");
            lua_pop(L, 1);
        }

        add_typedef(L, "va_list", "__builtin_va_list");
        add_typedef(L, "va_list", "__gnuc_va_list");
    }

    assert(lua_gettop(L) == 1);

    /* setup ABI params table */
    push_upval(L, &abi_key);

    lua_pop(L, 1); /* abi tbl */

    /* GC table - shouldn't pin cdata values */
    push_upval(L, &gc_key);
    lua_newtable(L);
    lua_pushliteral(L, "k");
    lua_setfield(L, -2, "__mode");
    lua_setmetatable(L, -2);
    lua_pop(L, 1); /* gc table */

    /* ffi.os */
#if defined OS_CE
    lua_pushliteral(L, "WindowsCE");
#elif defined OS_WIN
    lua_pushliteral(L, "Windows");
#elif defined OS_OSX
    lua_pushliteral(L, "OSX");
#elif defined OS_LINUX
    lua_pushliteral(L, "Linux");
#elif defined OS_BSD
    lua_pushliteral(L, "BSD");
#elif defined OS_POSIX
    lua_pushliteral(L, "POSIX");
#else
    lua_pushliteral(L, "Other");
#endif
    lua_setfield(L, 1, "os");

    assert(lua_gettop(L) == 1);

    return 0;
}

static void setup_mt(lua_State* L, const luaL_Reg* mt, int upvals) {
    lua_pushboolean(L, 1);
    lua_setfield(L, -upvals - 2, "__metatable");
    luaL_setfuncs(L, mt, upvals);
}

int luaopen_ffi(lua_State* L) {
    lua_settop(L, 0);

    lua_newtable(L);
    set_upval(L, &niluv_key);

    lua_newtable(L);
    setup_mt(L, ctype_mt, 0);
    set_upval(L, &ctype_mt_key);

    lua_newtable(L);
    set_upval(L, &gc_key);

    lua_newtable(L);
    push_upval(L, &gc_key);
    setup_mt(L, cdata_mt, 1);
    set_upval(L, &cdata_mt_key);

    lua_newtable(L);
    setup_mt(L, cmodule_mt, 0);
    set_upval(L, &cmodule_mt_key);

    lua_newtable(L);
    set_upval(L, &constants_key);

    lua_newtable(L);
    set_upval(L, &types_key);

    lua_newtable(L);
    set_upval(L, &functions_key);

    lua_newtable(L);
    set_upval(L, &asmname_key);

    lua_newtable(L);
    set_upval(L, &abi_key);

    lua_pushinteger(L, 1);
    set_upval(L, &next_unnamed_key);

    assert(lua_gettop(L) == 0);

    /* ffi table */
    lua_newtable(L);
    luaL_setfuncs(L, ffi_reg, 0);

    /* setup_upvals(ffi tbl) */
    lua_pushcfunction(L, &setup_upvals);
    lua_pushvalue(L, 1);
    lua_call(L, 1, 0);

    assert(lua_gettop(L) == 1);

    lua_getglobal(L, "tonumber");
    lua_pushcclosure(L, &ffi_number, 1);
    lua_pushvalue(L, -1);
    lua_setglobal(L, "tonumber");
    lua_setfield(L, -2, "number"); /* ffi.number */

    return 1;
}

static luaL_Reg preload_list[] = {{"ffi", luaopen_ffi}, {NULL, NULL}};

void preload_ffi(lua_State* L) {
    lua_getglobal(L, "package");
    lua_getfield(L, -1, "preload");
    luaL_setfuncs(L, preload_list, 0);
    lua_pop(L, 2);
}
