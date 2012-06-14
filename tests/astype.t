
local bar = macro(function(ctx,typ)
	
	return terralib.newtree(typ, { kind = terralib.kinds.literal, type = double, value = 4.0 })
	
end)

terra foo()
	var a : int = bar(int,int16,int32)
	return a
end

foo()
