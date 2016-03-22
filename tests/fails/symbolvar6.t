if not require("fail") then return end
local a = symbol(double)
local b = {3}

local c = symbol(int)
local d = {}


terra foo()
	var [a],[b] = 1.25,3
	var [c],[d] = 3.25
	return [a] + [c]
end

local test = require("test")

test.eq(foo(),4.25)
