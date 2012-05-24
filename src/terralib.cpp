#include "terralib.h"

static const char data[] = {

#include "terralib.def"
    
'\0'
};
size_t terra_library(const char ** tdata) {
    *tdata = data;
    return sizeof(data) - 1;
}