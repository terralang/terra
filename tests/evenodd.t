terra iseven(a : uint) : bool
	if a == 0 then
		return true
	else
		return isodd(a - 1)
	end
end and
terra isodd(a : uint) : bool
	if a == 0 then
		return false
	else
		return iseven(a - 1)
	end
end

local test = require("test")
test.eq(iseven(3),0)
test.eq(iseven(2),1)
test.eq(isodd(3),1)
test.eq(isodd(2),0)
