
struct A { a : int }
A.methods.foo = terra(self : A)
	return self.a
end

terra A:foo() 
	return self.a
end


terra doit()
	var a = A { 3 }
	return a:foo()
end
local test = require("test")
test.eq(doit(),7)