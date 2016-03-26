if not require("fail") then return end


local e = label()
A = terralib.types.newstruct("A")
A.entries:insert({ field = "a", type = int})
A.entries:insert({ field = e, type = int })


local b =  label()
A.methods[b] = terra(self : &A) return 3 end

local f = label()

terra foo()
	var a : A
	a.[e] = 3
  a.[f] = 4
	return a:[b]() + a.[e]
end

local test = require("test")
test.eq(foo(),6)
