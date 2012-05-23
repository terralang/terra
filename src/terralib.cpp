#include "terralib.h"

static const char data[] = {

#include "terralib.def"
    
'\n'
};
size_t terra_library(const char ** tdata) {
    *tdata = data;
    return sizeof(data);
}