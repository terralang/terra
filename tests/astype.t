
local bar = macro(function(ctx,typ)
	return terralib.newtree(typ, { kind = terralib.kinds.literal, type = double, value = 4.0 })
	
end)

local bar2 = macro(function(ctx,typ)
	return terralib.newtree(typ, { kind = terralib.kinds["var"], type = double, name = "a" })
	
end)


local bar3 = macro(function(ctx,a,b)
    return {a,b}
end)

terra up(v : &int)
    @v = @v + 1
end
terra foo() : int
	var a : int = bar(int,int16,int32)
	bar2(int) = bar2(int) + 5
	bar3(up(&a),up(&a))
	return a
end

local test = require("test")
test.eq(11,foo())
