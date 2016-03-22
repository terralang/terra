local foo = terralib.overloadedfunction("foo")
foo:adddefinition(terra(a : int)
	return 1
end)

foo:adddefinition(terra(a : double)
	return 2
end)

terra doit()
	return foo(2.5)
end

local test = require("test")
test.eq(doit(),2)