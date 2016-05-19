ffi = require 'ffi'


ffi.cdef [[
typedef struct FFIDefined {
    int a;
} FFIDefined;
]]

C = terralib.includecstring [[
typedef struct FFIDefined {
    int a;
} FFIDefined;
]]

r = terralib.new(C.FFIDefined,{})