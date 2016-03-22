
local foo = terralib.overloadedfunction("foo")
foo:adddefinition(terra(a : int)
	return a
end)

foo:adddefinition(terra(a : int, b : int)
	return a + b
end)

local test = require("test")
test.eq(foo:getdefinitions()[1](1) + foo:getdefinitions()[2](3,4), 8)