/* vim: ts=4 sw=4 sts=4 et tw=78
 *
 * Copyright (c) 2011 James R. McKaskill
 *
 * This software is licensed under the stock MIT license:
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 *
 * ----------------------------------------------------------------------------
 */

#ifndef _tffi_h
#define _tffi_h

#ifdef _MSC_VER
#define _CRT_SECURE_NO_WARNINGS
#endif

#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

#ifdef __cplusplus
extern "C" {
#include <lua.h>
#include <lauxlib.h>
}
#define EXTERN_C extern "C"
#else
#include <lua.h>
#include <lauxlib.h>
#define EXTERN_C extern
#endif

#ifdef _WIN32
#include <windows.h>
#else
#include <errno.h>
#include <unistd.h>
#include <dlfcn.h>
#include <sys/mman.h>
#endif

#if __STDC_VERSION__ + 0 >= 199901L
#include <complex.h>
#define HAVE_COMPLEX
#define HAVE_LONG_DOUBLE
#endif

#if defined LUA_FFI_BUILD_AS_DLL
#define EXPORT __declspec(dllexport)
#elif defined __GNUC__
#define EXPORT __attribute__((visibility("default")))
#else
#define EXPORT
#endif

EXTERN_C EXPORT int luaopen_ffi(lua_State* L);

static int lua_absindex2(lua_State* L, int idx) {
    return (LUA_REGISTRYINDEX <= idx && idx < 0) ? lua_gettop(L) + idx + 1 : idx;
}
/* use our own version of lua_absindex such that lua_absindex(L, 0) == 0 */
#define lua_absindex(L, idx) lua_absindex2(L, idx)

#if LUA_VERSION_NUM == 501
#define lua_setuservalue lua_setfenv
#define lua_getuservalue lua_getfenv
#define lua_rawlen lua_objlen
static char* luaL_prepbuffsize(luaL_Buffer* B, size_t sz) {
    if (sz > LUAL_BUFFERSIZE) {
        luaL_error(B->L, "string too long");
    }
    return luaL_prepbuffer(B);
}
#endif

/* architectures */
#if defined _WIN32 && defined UNDER_CE
#define OS_CE
#elif defined _WIN32
#define OS_WIN
#elif defined __APPLE__ && defined __MACH__
#define OS_OSX
#elif defined __linux__
#define OS_LINUX
#elif defined __FreeBSD__ || defined __OpenBSD__ || defined __NetBSD__
#define OS_BSD
#elif defined unix || defined __unix__ || defined __unix || defined _POSIX_VERSION || \
        defined _XOPEN_VERSION
#define OS_POSIX
#endif

#ifdef _WIN32

#ifdef UNDER_CE
static void* DoLoadLibraryA(const char* name) {
    wchar_t buf[MAX_PATH];
    int sz = MultiByteToWideChar(CP_UTF8, 0, name, -1, buf, 512);
    if (sz > 0) {
        buf[sz] = 0;
        return LoadLibraryW(buf);
    } else {
        return NULL;
    }
}
#define LoadLibraryA DoLoadLibraryA
#else
#define GetProcAddressA GetProcAddress
#endif

#define LIB_FORMAT_1 "%s.dll"
#define AllocPage(size) VirtualAlloc(NULL, size, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE)
#define FreePage(data, size) VirtualFree(data, 0, MEM_RELEASE)
#define EnableExecute(data, size)                               \
    do {                                                        \
        DWORD old;                                              \
        VirtualProtect(data, size, PAGE_EXECUTE, &old);         \
        FlushInstructionCache(GetCurrentProcess(), data, size); \
    } while (0)
#define EnableWrite(data, size)                           \
    do {                                                  \
        DWORD old;                                        \
        VirtualProtect(data, size, PAGE_READWRITE, &old); \
    } while (0)

#else
#define LIB_FORMAT_1 "%s.so"
#define LIB_FORMAT_2 "lib%s.so"
#define LoadLibraryA(name) dlopen(name, RTLD_LAZY | RTLD_GLOBAL)
#define GetProcAddressA(lib, name) dlsym(lib, name)
#define AllocPage(size) \
    mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0)
#define FreePage(data, size) munmap(data, size)
#define EnableExecute(data, size) mprotect(data, size, PROT_READ | PROT_EXEC)
#define EnableWrite(data, size) mprotect(data, size, PROT_READ | PROT_WRITE)
#endif

#define ALLOW_MISALIGNED_ACCESS

struct token;

struct parser {
    int line;
    const char* next;
    const char* prev;
    unsigned align_mask;
};

#define ALIGN_DOWN(PTR, MASK) (((uintptr_t)(PTR)) & (~((uintptr_t)(MASK))))
#define ALIGN_UP(PTR, MASK) \
    ((((uintptr_t)(PTR)) + ((uintptr_t)(MASK))) & (~((uintptr_t)(MASK))))

/* struct cdata/struct ctype */

#define PTR_ALIGN_MASK (sizeof(void*) - 1)
#define FUNCTION_ALIGN_MASK (sizeof(void (*)()) - 1)
#define DEFAULT_ALIGN_MASK 7

#ifdef OS_OSX
/* TODO: figure out why the alignof trick doesn't work on OS X */
#define ALIGNED_DEFAULT 7
#elif defined __GNUC__
#define ALIGNED_DEFAULT (__alignof__(void* __attribute__((aligned))) - 1)
#else
#define ALIGNED_DEFAULT PTR_ALIGN_MASK
#endif

extern int ctype_mt_key;
extern int cdata_mt_key;
extern int cmodule_mt_key;
extern int constants_key;
extern int types_key;
extern int gc_key;
extern int functions_key;
extern int next_unnamed_key;
extern int niluv_key;
extern int asmname_key;

int equals_upval(lua_State* L, int idx, int* key);
void push_upval(lua_State* L, int* key);
void set_upval(lua_State* L, int* key);

/* both ctype and cdata are stored as userdatas
 *
 * usr value is a table shared between the related subtypes which has:
 * name -> member ctype (for structs and unions)
 * +ves -> member ctype - in memory order (for structs)
 * +ves -> argument ctype (for function prototypes)
 * 0 -> return ctype (for function prototypes)
 * light userdata -> misc
 */

enum {
    C_CALL,
    STD_CALL,
    FAST_CALL,
};

enum {
    INVALID_TYPE,
    VOID_TYPE,
    FLOAT_TYPE,
    DOUBLE_TYPE,
    LONG_DOUBLE_TYPE,
    COMPLEX_FLOAT_TYPE,
    COMPLEX_DOUBLE_TYPE,
    COMPLEX_LONG_DOUBLE_TYPE,
    BOOL_TYPE,
    INT8_TYPE,
    INT16_TYPE,
    INT32_TYPE,
    INT64_TYPE,
    INTPTR_TYPE,
    ENUM_TYPE,
    UNION_TYPE,
    STRUCT_TYPE,
    FUNCTION_TYPE,
    FUNCTION_PTR_TYPE,
};

#define IS_CHAR_UNSIGNED (((char)-1) > 0)
#define IS_COMPLEX(type) ((type) == COMPLEX_FLOAT_TYPE || (type) == COMPLEX_DOUBLE_TYPE)

#define POINTER_BITS 2
#define POINTER_MAX ((1 << POINTER_BITS) - 1)

#define ALIGNOF(S) ((int)((char*)&S.v - (char*)&S - 1))

/* Note: if adding a new member that is associated with a struct/union
 * definition then it needs to be copied over in ctype.c:set_defined for when
 * we create types based off of the declaration alone.
 *
 * Since this is used as a header for every ctype and cdata, and we create a
 * ton of them on the stack, we try and minimise its size.
 */
struct ctype {
    size_t base_size; /* size of the base type in bytes */

    union {
        /* valid if is_bitfield */
        struct {
            /* size of bitfield in bits */
            unsigned bit_size : 7;
            /* offset within the current byte between 0-63 */
            unsigned bit_offset : 6;
        };
        /* Valid if is_array */
        size_t array_size;
        /* Valid for is_variable_struct or is_variable_array. If
         * variable_size_known (only used for is_variable_struct) then this is
         * the total increment otherwise this is the per element increment.
         */
        size_t variable_increment;
    };
    size_t offset;
    unsigned align_mask : 4; /* as (align bytes - 1) eg 7 gives 8 byte alignment */
    unsigned pointers : POINTER_BITS; /* number of dereferences to get to the base type
                                         including +1 for arrays */
    unsigned const_mask : POINTER_MAX + 1; /* const pointer mask, LSB is current pointer,
                                              +1 for the whether the base type is const */
    unsigned type : 5;                     /* value given by type enum above */
    unsigned is_reference : 1;
    unsigned is_array : 1;
    unsigned is_defined : 1;
    unsigned is_null : 1;
    unsigned has_member_name : 1;
    unsigned calling_convention : 2;
    unsigned has_var_arg : 1;
    unsigned is_variable_array : 1; /* set for variable array types where we don't know
                                       the variable size yet */
    unsigned is_variable_struct : 1;
    unsigned variable_size_known : 1; /* used for variable structs after we know the
                                         variable size */
    unsigned is_bitfield : 1;
    unsigned has_bitfield : 1;
    unsigned is_packed : 1;
    unsigned is_unsigned : 1;
};

#ifdef _MSC_VER
__declspec(align(16))
#endif
        struct cdata {
    const struct ctype type
#ifdef __GNUC__
            __attribute__((aligned(16)))
#endif
            ;
};

typedef void (*cfunction)(void);

#ifdef HAVE_COMPLEX
typedef double complex complex_double;
typedef float complex complex_float;
#else
typedef struct {
    double real, imag;
} complex_double;

typedef struct {
    float real, imag;
} complex_float;

static double creal(complex_double c) { return c.real; }
static float crealf(complex_float c) { return c.real; }

static double cimag(complex_double c) { return c.imag; }
static float cimagf(complex_float c) { return c.imag; }
#endif

void set_defined(lua_State* L, int ct_usr, struct ctype* ct);
struct ctype* push_ctype(lua_State* L, int ct_usr, const struct ctype* ct);
void* push_cdata(lua_State* L, int ct_usr, const struct ctype* ct); /* called from asm */
void check_ctype(lua_State* L, int idx, struct ctype* ct);
void* to_cdata(lua_State* L, int idx, struct ctype* ct);
void* check_cdata(lua_State* L, int idx, struct ctype* ct);
size_t ctype_size(lua_State* L, const struct ctype* ct);

int parse_type(lua_State* L, struct parser* P, struct ctype* type);
void parse_argument(lua_State* L, struct parser* P, int ct_usr, struct ctype* type,
                    struct token* name, struct parser* asmname);
void push_type_name(lua_State* L, int usr, const struct ctype* ct);

int push_user_mt(lua_State* L, int ct_usr, const struct ctype* ct);

int ffi_cdef(lua_State* L);

/* WARNING: assembly needs to be updated for prototype changes of these functions */
int check_bool(lua_State* L, int idx);
double check_double(lua_State* L, int idx);
double check_complex_imag(lua_State* L, int idx);
float check_float(lua_State* L, int idx);
uint64_t check_uint64(lua_State* L, int idx);
int64_t check_int64(lua_State* L, int idx);
int32_t check_int32(lua_State* L, int idx);
uint32_t check_uint32(lua_State* L, int idx);
uintptr_t check_uintptr(lua_State* L, int idx);
int32_t check_enum(lua_State* L, int idx, int to_usr, const struct ctype* tt);
/* these two will always push a value so that we can create structs/functions on the fly
 */
void* check_typed_pointer(lua_State* L, int idx, int to_usr, const struct ctype* tt);
cfunction check_typed_cfunction(lua_State* L, int idx, int to_usr,
                                const struct ctype* tt);
complex_double check_complex_double(lua_State* L, int idx);
complex_float check_complex_float(lua_State* L, int idx);

void unpack_varargs_stack(lua_State* L, int first, int last, char* to);
void unpack_varargs_reg(lua_State* L, int first, int last, char* to);

void unpack_varargs_stack_skip(lua_State* L, int first, int last, int ints_to_skip,
                               int floats_to_skip, char* to);
void unpack_varargs_float(lua_State* L, int first, int last, int max, char* to);
void unpack_varargs_int(lua_State* L, int first, int last, int max, char* to);

#endif
