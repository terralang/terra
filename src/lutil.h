#ifndef lutil_h
#define lutil_h

#include "terrastate.h"

#include <stdio.h>
#include <stdint.h>
#include <limits.h>

extern "C" {
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
}

#define cast(t, exp) ((t)(exp))
#define cast_byte(i) cast(lu_byte, (i))
#define cast_num(i) cast(luaP_Number, (i))
#define cast_int(i) cast(int, (i))
#define cast_uchar(i) cast(unsigned char, (i))

typedef double luaP_Number;
typedef unsigned char lu_byte;
typedef uint32_t lu_int32;
#define MAX_SIZET ((size_t)(~(size_t)0) - 2)

typedef struct TString {
    const char *string;
    lu_byte reserved;
} TString;

typedef const char *(*luaP_Reader)(lua_State *L, void *ud, size_t *sz);

/*
@@ LUAI_FUNC is a mark for all extern functions that are not to be
@* exported to outside modules.
@@ LUAI_DDEF and LUAI_DDEC are marks for all extern (const) variables
@* that are not to be exported to outside modules (LUAI_DDEF for
@* definitions and LUAI_DDEC for declarations).
** CHANGE them if you need to mark them in some special way. Elf/gcc
** (versions 3.2 and later) mark them as "hidden" to optimize access
** when Lua is compiled as a shared library. Not all elf targets support
** this attribute. Unfortunately, gcc does not offer a way to check
** whether the target offers that support, and those without support
** give a warning about it. To avoid these warnings, change to the
** default definition.
*/
#if defined(__GNUC__) && ((__GNUC__ * 100 + __GNUC_MINOR__) >= 302) && \
        defined(__ELF__) /* { */
#define LUAI_FUNC __attribute__((visibility("hidden"))) extern
#define LUAI_DDEC LUAI_FUNC
#define LUAI_DDEF /* empty */

#else /* }{ */
#define LUAI_FUNC extern
#define LUAI_DDEC extern
#define LUAI_DDEF /* empty */
#endif            /* } */

#if defined(__GNUC__)
#define l_noret void __attribute__((noreturn))
#elif defined(_MSC_VER)
#define l_noret void __declspec(noreturn)
#else
#define l_noret void
#endif

/* minimum size for string buffer */
#if !defined(LUA_MINBUFFER)
#define LUA_MINBUFFER 32
#endif

/*
@@ LUA_IDSIZE gives the maximum size for the description of the source
@* of a function in debug information.
** CHANGE it if you want a different size.
*/
#define LUA_IDSIZE 60

#define MAX_INT (INT_MAX - 2) /* maximum value of an int (-2 for safety) */

/*
** Marks the end of a patch list. It is an invalid value both as an absolute
** address, and as a list link (would link an element to itself).
*/
#define NO_JUMP (-1)

/*
** maximum depth for nested C calls and syntactical nested non-terminals
** in a program. (Value must fit in an unsigned short int.)
*/
#if !defined(LUAI_MAXCCALLS)
#define LUAI_MAXCCALLS 200
#endif

/*
@@ LUA_QL describes how error messages quote program elements.
** CHANGE it if you want a different appearance.
*/
#define LUA_QL(x) "'" x "'"
#define LUA_QS LUA_QL("%s")

#endif
