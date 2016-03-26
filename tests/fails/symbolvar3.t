if not require("fail") then return end


local a = symbol(int)

local q = quote 
	var [a] = 2
	[a] = [a] + 1
end

terra foo()
	do
	q
	end
	return [a]
end

local test = require("test")
test.eq(3,foo())
