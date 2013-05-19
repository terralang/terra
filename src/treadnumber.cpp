/* See Copyright Notice in ../LICENSE.txt */

#include "treadnumber.h"
extern "C" {
#include "lj_strscan.h"
}

int treadnumber(const char * buf, ReadNumber * result, int allowsuffixes, int allowimag) {
	TValue o;
    int opt = STRSCAN_OPT_TOINT;
    if(allowsuffixes)
        opt |= STRSCAN_OPT_LL | STRSCAN_OPT_C;
    if(allowimag)
        opt |= STRSCAN_OPT_IMAG;
    
    StrScanFmt fmt = lj_strscan_scan((const uint8_t*)buf, &o, opt);
    result->flags = 0;
    switch(fmt) {
        case STRSCAN_ERROR:
            return 1;
        case STRSCAN_IMAG:
            /* terra doesn't have imag numbers, so allowimag will be false for terra code */
            break;
        case STRSCAN_NUM:
            result->d = o.n;
            break;
        case STRSCAN_INT:
            result->flags = ReadNumber::F_ISINTEGER;
            result->i = o.i;
            break;
        case STRSCAN_U32:
            result->flags = ReadNumber::F_ISINTEGER | ReadNumber::F_ISUNSIGNED;
            result->i = o.i;
            break;
        case STRSCAN_I64:
            result->flags = ReadNumber::F_ISINTEGER | ReadNumber::F_IS8BYTES;
            result->i = o.u64;
            break;
        case STRSCAN_U64:
            result->flags = ReadNumber::F_ISINTEGER | ReadNumber::F_IS8BYTES | ReadNumber::F_ISUNSIGNED;
            result->i = o.u64;
            break;
    }
    return 0;
}