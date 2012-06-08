local test = require("test")

terra foo(a : double, b : double, c : double) : bool
    return a < b and b < c
end

test.eq(foo(1,2,3),1)
test.eq(foo(1,2,1),0)
test.eq(foo(2,1,2),0)