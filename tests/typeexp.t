terra foo(a : int)
   var b : &a.type = &a
   return @b
end

local test = require("test")

test.eq(foo(3),3)