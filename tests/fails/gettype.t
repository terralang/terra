if not require("fail") then return end



function makestuff(a)
	local T = a:gettype()
	local struct ST {
		a : T
	}
	return `ST { a }
end

makestuff = macro(makestuff)

terra useit()
	return makestuff(true).a,makestuff(3.0).a,makestuff(makestuff).a
end

local a,b = useit()
assert(a == true)
assert(b == 3)
