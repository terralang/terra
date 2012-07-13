
local bar2 = macro(function(ctx,typ)
	return terralib.newtree(typ.tree, { kind = terralib.kinds["var"], name = "a" })
	
end)

terra foo() : int
	var a = 3
	bar2(int) = bar2(int) + 5
	return a
end

local test = require("test")
test.eq(8,foo())
