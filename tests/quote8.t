a = {}

local c = terralib.includec("stdio.h")


a.c = {`1,`2,`3}

a.b = quote
    return a.c,a.c
end


terra foo()
    a.b
end


local test = require("test")
local z,a,b,c = foo()
test.eq(z,1)
test.eq(a,1)
test.eq(b,2)
test.eq(c,3)
