C = terralib.includec("stdio.h")

local ffi = require("ffi")

struct A {
}

terra final(a : &A)
    C.printf("final\n")
end

a = terralib.new(A)
ffi.gc(a,function(a)
print("GC CALLED")
return final(a) end)
