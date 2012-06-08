local test = require("test")

terra foo(a : double, b : double, c : double) : bool
    return a < b or b < c
end

test.eq(foo(1,2,1),1)
test.eq(foo(2,1,2),1)
test.eq(foo(3,2,1),0)