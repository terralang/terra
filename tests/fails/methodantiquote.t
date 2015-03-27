if not require("fail") then return end
--the zero line
M = {}
struct M.B {a : int, b : int}

terra M.B:foo(a : int)
    return self.a + a
end


local avar = 2

terra bar()
    var b : M.B = { 1,2 }
    return b:[avar](3)
end

test = require("test")
test.eq(bar(),4)
