
local a = symbol(int)
terra foo([a], b : int)
	return [a] + b
end

local test = require("test")

test.eq(foo(1,2),3)