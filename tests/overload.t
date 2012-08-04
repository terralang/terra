
terra foo(a : int)
	return 1
end

terra foo(a : &int8)
	return 2
end

terra doit()
	return foo(1) + foo("what")
end

local test = require("test")
test.eq(doit(),3)