
local c = terralib.includec("mytest.h")


terra foo()
    var a : int = 3
    return c.myfoobarthing(1,2,3.5,&a) + a
end


local test = require("test")

test.eq(foo(),15)
test.eq(c.myotherthing(1,2),3)