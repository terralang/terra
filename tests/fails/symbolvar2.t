if not require("fail") then return end


local a = symbol()

local q = quote 
	[a] = [a] + 1
end

terra foo()
	q
	return [a]
end

local test = require("test")
test.eq(3,foo())
