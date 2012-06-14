
terra foo() : (double, double)
	return 1.0,3.0
end

struct A {c : int, a : int, b : double }

terra bar()
	var a : A = {1,foo()}
	return a.c + a.a + a.b
end

local test = require("test")
test.eq(5,bar())