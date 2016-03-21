if not require("fail") then return end
local c = symbol(int)
local b = 
quote
	var [c]  = 3
in
	c,c+1
end

terra f3()
	var what = (b)
	return ([c])
end
assert(f3() == 3)
