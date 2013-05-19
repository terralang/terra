#ifndef _treadnumber_h
#define _treadnumber_h

/* wrapper around LuaJIT's read number parsing code
   used in the lexer so that we match LuaJIT's number format as closely as possible 
   NYI - negative numbers, since '-' is treated as a unary minus we only ever encounter
   positive numbers, readnumber will not handle negatives correctly
*/

#include <stdint.h>

struct ReadNumber {
	union {
		uint64_t i;
		double d;
	};
	enum {
		F_ISINTEGER = 1,
		F_ISUNSIGNED = 2,
		F_IS8BYTES = 4,
	};
	int flags;
};
int treadnumber(const char * buf, ReadNumber * result, int allowsuffixes, int allowimag);
#endif