
local bar = macro(function(ctx,typ)
	return terralib.newtree(typ.tree, { kind = terralib.kinds.literal, type = double, value = 4.0 })
	
end)

local bar2 = macro(function(ctx,typ)
	return terralib.newtree(typ.tree, { kind = terralib.kinds["var"], name = "a" })
	
end)


local bar3 = macro(function(ctx,a,b)
    return {a.tree,b.tree}
end)

terra up(v : &int)
    @v = @v + 1
end

local bar4 = macro(function()
    terra myfn()
        return 42
    end
    return { a_fn = myfn }
end)

var moo : int = 3

local bar4 = macro(function()
    terra myfn()
        return 42
    end
    return { a_fn = myfn }
end)

local bar5 = macro(function()
    return moo
end)

terra foo() : int
	var a : int = bar(int,int16,int32)
	bar2(int) = bar2(int) + 5
	bar3(up(&a),up(&a))
	bar5() = bar5() + 1
	return a + bar4().a_fn() + moo
end

local test = require("test")
test.eq(57,foo())
