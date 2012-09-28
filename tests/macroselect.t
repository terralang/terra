
struct A { a : int, b : int }

local c = "b"
terra foo()
	var a = A {1,2}
	return terralib.select(a,c)
end

local test = require("test")
test.eq(foo(),2)