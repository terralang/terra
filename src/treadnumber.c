/* See Copyright Notice in ../LICENSE.txt */

#include "treadnumber.h"

#include "lj_strscan.h"

int treadnumber(const char* buf, ReadNumber* result, int cstylesuffixes) {
    TLJ_TValue o;
    StrScanFmt fmt;
    int opt = STRSCAN_OPT_TOINT | STRSCAN_OPT_LL;
    if (cstylesuffixes)
        opt |= STRSCAN_OPT_C;
    else
        opt |= STRSCAN_OPT_IMAG;

    fmt = terra_lj_strscan_scan((const uint8_t*)buf, &o, opt);
    result->flags = 0;
    switch (fmt) {
        case STRSCAN_ERROR:
            return 1;
        case STRSCAN_IMAG:
            /* terra doesn't have imag numbers, so allowimag will be false for terra code
             */
            break;
        case STRSCAN_NUM:
            result->d = o.n;
            break;
        case STRSCAN_INT:
            result->flags = F_ISINTEGER;
            result->i = o.i;
            break;
        case STRSCAN_U32:
            result->flags = F_ISINTEGER | F_ISUNSIGNED;
            result->i = o.i;
            break;
        case STRSCAN_I64:
            result->flags = F_ISINTEGER | F_IS8BYTES;
            result->i = o.u64;
            break;
        case STRSCAN_U64:
            result->flags = F_ISINTEGER | F_IS8BYTES | F_ISUNSIGNED;
            result->i = o.u64;
            break;
    }
    return 0;
}
