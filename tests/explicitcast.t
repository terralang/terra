
terra foo()
    var a = 256+3
    var c = (&a):as(intptr)
    var d = c:as(&int64)
    var fi = (true):as(int)
    var what = @(&a):as(&int8)
    return @d,fi,what
end

local test = require("test")
local a,b,c = foo()
test.eq(a,256+3)
test.eq(b,1)
test.eq(c,3)