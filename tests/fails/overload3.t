if not require("fail") then return end

struct A { a : int }
struct B { a : int, b : int}

terra foo(a : A)
	return 1
end

terra foo(a : B)
	return 2
end

terra doit()
	return foo({1}) + foo({1,2})
end

local test = require("test")
test.eq(doit(),4)
