

local e = symbol()
A = terralib.types.newstruct("A")
A:addentry("a",int)
A:addentry(e,int)


local b =  symbol()
A.methods[b] = terra(self : &A) return 3 end


terra foo()
	var a : A
	a.[e] = 3
	return a:[b]() + a.[e]
end

local test = require("test")
test.eq(foo(),6)