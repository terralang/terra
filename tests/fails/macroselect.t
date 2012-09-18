
struct A { a : int, b : int }

local c = 1
terra foo()
	var a = A {1,2}
	return terralib.select(a,c)
end

local test = require("test")
test.eq(foo(),2)