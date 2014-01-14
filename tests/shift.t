local test = require("test")

terra foo(a : int)
    return 1 << 2, a >> 1, -4 >> 1, uint32(-a) >> 1
end

local a,b,c,d = foo(4)
test.eq(a,4)
test.eq(b,2)
test.eq(d,2147483646)
