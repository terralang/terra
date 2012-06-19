
terra foo()
    return 4
end

terra bar()
    return 5
end

terra bar3(fn: {} -> int64)
	return fn()
end

terra baz(a : int64)
    var afn = foo
    if a > 2 then
       afn = bar
    end
    return bar3(@afn)
end

local test = require("test")
test.eq(baz(1),4)
test.eq(baz(3),5)