local foo = terralib.overloadedfunction("foo")
foo:adddefinition(terra(a : {int} )
	return 1
end)

foo:adddefinition(terra(a : {int,int} )
	return 2
end)

terra doit()
	return foo({1,2}) + foo({1,2})
end

local test = require("test")
test.eq(doit(),4)