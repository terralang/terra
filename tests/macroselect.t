
struct A { a : int, b : int }

local c = "b"
terra foo()
	var a = A {1,2}
	var b = &a
	return a[c] + b[c] + b[0][c]
end

local test = require("test")
test.eq(foo(),6)