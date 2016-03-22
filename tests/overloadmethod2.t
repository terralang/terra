
struct A { a : int }
A.methods.foo = terralib.overloadedfunction("foo")
A.methods.foo:adddefinition(terra(self : A, a : int)
	return self.a + a
end)

A.methods.foo:adddefinition(terra(self :&A) 
	return self.a
end)


terra doit()
	var a = A { 3 }
	return a:foo() + a:foo(1)
end
local test = require("test")
test.eq(doit(),7)