if not require("fail") then return end

local b = 1
local dd = "d"
local c = label()

terra foo()
	var a = { [b], [c] = 2, [dd] = 3, r = 4}
	return a._0 + a.[c] + a.d + a.r
end

local test = require("test")
test.eq(foo(),10)
