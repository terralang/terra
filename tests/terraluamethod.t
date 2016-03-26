struct A { a : int }

local up = function(self,b)
	self.a = self.a + 1 + (b or 0)
end
A.methods.up0 = terralib.cast(&A -> {},up)
A.methods.up1 = terralib.cast({&A,int} -> {}, up)

terra foo()
	var a = A { 1 }
	a:up0()
	var b = &a
	b:up1(4)
	return a.a
end

local test = require("test")
test.eq(foo(),7)