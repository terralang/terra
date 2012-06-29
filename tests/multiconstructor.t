
terra foo() : {double, double}
	return 1.0,3.0
end

struct A {c : int, a : int, b : double }

terra bar()
	var a : A = {1,foo()}
	var b : A = {1,2,(foo())}
	var c : A = {1,2,b = foo()}
	return a.c + a.a + a.b + b.c + c.c
end

local test = require("test")
test.eq(7,bar())