/* See Copyright Notice in ../LICENSE.txt */

#include <math.h>
#include <string.h>
#include "lctype.h"
#include "lobject.h"
#include "llex.h"

static int isneg (const char **s) {
  if (**s == '-') { (*s)++; return 1; }
  else if (**s == '+') (*s)++;
  return 0;
}


int luaO_hexavalue (int c) {
  if (lisdigit(c)) return c - '0';
  else return ltolower(c) - 'a' + 10;
}

static luaP_Number readhexa (const char **s, luaP_Number r, int *count) {
  for (; lisxdigit(cast_uchar(**s)); (*s)++) {  /* read integer part */
    r = (r * 16.0) + cast_num(luaO_hexavalue(cast_uchar(**s)));
    (*count)++;
  }
  return r;
}


/*
** convert an hexadecimal numeric string to a number, following
** C99 specification for 'strtod'
*/
static luaP_Number luaP_strx2number (const char *s, char **endptr) {
  luaP_Number r = 0.0;
  int e = 0, i = 0;
  int neg = 0;  /* 1 if number is negative */
  *endptr = const_cast<char *>(cast(const char *, s));  /* nothing is valid yet */
  while (lisspace(cast_uchar(*s))) s++;  /* skip initial spaces */
  neg = isneg(&s);  /* check signal */
  if (!(*s == '0' && (*(s + 1) == 'x' || *(s + 1) == 'X')))  /* check '0x' */
    return 0.0;  /* invalid format (no '0x') */
  s += 2;  /* skip '0x' */
  r = readhexa(&s, r, &i);  /* read integer part */
  if (*s == '.') {
    s++;  /* skip dot */
    r = readhexa(&s, r, &e);  /* read fractional part */
  }
  if (i == 0 && e == 0)
    return 0.0;  /* invalid format (no digit) */
  e *= -4;  /* each fractional digit divides value by 2^-4 */
  *endptr = const_cast<char *>(cast(const char *, s));  /* valid up to here */
  if (*s == 'p' || *s == 'P') {  /* exponent part? */
    int exp1 = 0;
    int neg1;
    s++;  /* skip 'p' */
    neg1 = isneg(&s);  /* signal */
    if (!lisdigit(cast_uchar(*s)))
      goto ret;  /* must have at least one digit */
    while (lisdigit(cast_uchar(*s)))  /* read exponent */
      exp1 = exp1 * 10 + *(s++) - '0';
    if (neg1) exp1 = -exp1;
    e += exp1;
  }
  *endptr = const_cast<char *>(cast(const char *, s));  /* valid up to here */
 ret:
  if (neg) r = -r;
  return ldexp(r, e);
}



int luaO_str2d (const char *s, size_t len, luaP_Number *result) {
  char *endptr;
  if (strpbrk(s, "nN"))  /* reject 'inf' and 'nan' */
    return 0;
  else if (strpbrk(s, "xX"))  /* hexa? */
    *result = luaP_strx2number(s, &endptr);
  else
    *result = luaP_str2number(s, &endptr);
  if (endptr == s) return 0;  /* nothing recognized */
  while (lisspace(cast_uchar(*endptr))) endptr++;
  return (endptr == s + len);  /* OK if no trailing characters */
}


