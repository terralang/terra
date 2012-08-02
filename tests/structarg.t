--struct A { a : int, b : int}

terra A(a : struct { a : int, b : int})
	return a.a
end

terra foobar()
	var a = A { 3, 4}
	return a
end

local test = require("test")
test.eq(foobar(),3)