#ifndef _treadnumber_h
#define _treadnumber_h

/* wrapper around LuaJIT's read number parsing code
   used in the lexer so that we match LuaJIT's number format as closely as possible
   NYI - negative numbers, since '-' is treated as a unary minus we only ever encounter
   positive numbers, readnumber will not handle negatives correctly
*/

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    F_ISINTEGER = 1,
    F_ISUNSIGNED = 2,
    F_IS8BYTES = 4,
} ReadNumberFlags;

typedef struct {
    union {
        uint64_t i;
        double d;
    };
    int flags;
} ReadNumber;
int treadnumber(const char* buf, ReadNumber* result, int cstylesuffixes);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif