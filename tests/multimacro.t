
local bar = terralib.internalmacro(function(ctx,tree,typ,x)
	return {(`4.0).tree, x }
end)

local x,y,z = 1,2,3

terra foo() : int
	var a,b = bar(int,x + y + z)
	var c = bar(int,0)._0 + 1
	--bar2(int) = bar2(int) + 5
	--bar3(up(&a),up(&a))
	return a + b + c
end

local test = require("test")
test.eq(15,foo())
