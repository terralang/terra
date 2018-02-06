local test = require("test")

terra foo(x : int) : int
    return x
end
foo:setoptimized(false)

test.eq(foo(42),42)
