local foo = terralib.overloadedfunction("foo")
foo:adddefinition(terra(a : int)
	return 1
end)
foo:adddefinition(terra(a : &int8)
	return 2
end)

print(#foo.definitions)

terra doit()
	return foo(1) + foo("what")
end

local test = require("test")
test.eq(doit(),3)