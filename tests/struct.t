struct A { b : B }
struct B {a : int, b : int }

terra foo()
	var a : B
	a.a = 4
	a.b = 5
	return a.a + a.b
end

local test = require("test")

test.eq(foo(),9)

