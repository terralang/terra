if not require("fail") then return end

struct A { a : int, b : int }

local c = 1
terra foo()
	var a = A {1,2}
	return a.[c]
end

local test = require("test")
test.eq(foo(),2)
