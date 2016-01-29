/*
** String scanning.
** Copyright (C) 2005-2015 Mike Pall. See Copyright Notice in luajit.h
*/

/* SJT:
 LuaJIT does not expose its number parsing capabilities directly, but we wish to
 match them in Terra.  To do this, lj_strscan.[ch] have been copied over from the
 luajit source tree, function names have been changed to avoid symbol clashes (if
 the libluajit you link against hasn't been stripped), and as many other references to
 other internal luajit things have been replaced with the subsets needed to make
 lj_strscan_scan work.
*/

#ifndef TERRA_LJ_STRSCAN_H
#define TERRA_LJ_STRSCAN_H

#include <lua.h>

/* SJT: originally from lj_def.h ... */
#if defined(_MSC_VER)
/* MSVC is stuck in the last century and doesn't have C99's stdint.h. */
typedef unsigned __int8 uint8_t;
typedef __int64 int64_t;
typedef unsigned __int64 uint64_t;
typedef unsigned __int32 uint32_t;
typedef __int32 int32_t;
#elif defined(__symbian__)
/* Cough. */
typedef unsigned char uint8_t;
typedef long long int64_t;
typedef unsigned long long uint64_t;
#else
#include <stdint.h>
#endif


/* SJT: originally from lj_obj.h ... */
/* Tagged value. */
typedef union TLJ_TValue {
  uint64_t u64;		/* 64 bit pattern overlaps number. */
  int64_t i;
  lua_Number n;		/* Number object overlaps split tag/value object. */
} TLJ_TValue;

/* Options for accepted/returned formats. */
#define STRSCAN_OPT_TOINT	0x01  /* Convert to int32_t, if possible. */
#define STRSCAN_OPT_TONUM	0x02  /* Always convert to double. */
#define STRSCAN_OPT_IMAG	0x04
#define STRSCAN_OPT_LL		0x08
#define STRSCAN_OPT_C		0x10

/* Returned format. */
typedef enum {
  STRSCAN_ERROR,
  STRSCAN_NUM, STRSCAN_IMAG,
  STRSCAN_INT, STRSCAN_U32, STRSCAN_I64, STRSCAN_U64,
} StrScanFmt;

StrScanFmt terra_lj_strscan_scan(const uint8_t *p, TLJ_TValue *o, uint32_t opt);

#endif
