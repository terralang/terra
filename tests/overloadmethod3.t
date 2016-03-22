
struct A { a : int }

A.methods.foo = terralib.overloadedfunction("foo")
A.methods.foo:adddefinition(terra(self : A)
	return 2
end)

A.methods.foo:adddefinition(terra(self : &A) 
	return 1
end)


terra doit()
	var a = A { 3 }
	var pa = &a
	return a:foo() + pa:foo()
end
local test = require("test")
test.eq(doit(),4)