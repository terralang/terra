#ifndef lobject_h
#define lobject_h

#include <stdio.h>
#include <stdlib.h>
#include "putil.h"

/*
@@ lua_str2number converts a decimal numeric string to a number.
@@ lua_strx2number converts an hexadecimal numeric string to a number.
** In C99, 'strtod' do both conversions. C89, however, has no function
** to convert floating hexadecimal strings to numbers. For these
** systems, you can leave 'lua_strx2number' undefined and Lua will
** provide its own implementation.
*/
#define lua_str2number(s,p)	strtod((s), (p))
int luaO_str2d (const char *s, size_t len, lua_Number *result);
int luaO_hexavalue (int c);

/*
** `module' operation for hashing (size is always a power of 2)
*/
#define lmod(s,size) \
	(check_exp((size&(size-1))==0, (cast(int, (s) & ((size)-1)))))

/* internal assertions for in-house debugging */
#if defined(lua_assert)
#define check_exp(c,e)		(lua_assert(c), (e))
/* to avoid problems with conditions too long */
#define lua_longassert(c)	{ if (!(c)) lua_assert(0); }
#else
#define lua_assert(c)		((void)0)
#define check_exp(c,e)		(e)
#define lua_longassert(c)	((void)0)
#endif

#endif
