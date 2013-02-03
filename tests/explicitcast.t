
terra foo()
    var a = 256+3
    var c = intptr(&a)
    var d = [&int64](c)
    var fi = int(true)
    var what = @[&int8](&a)
    return @d,fi,what
end

local test = require("test")
local a,b,c = foo()
test.eq(a,256+3)
test.eq(b,1)
test.eq(c,3)