if not require("fail") then return end


terra foo2()
	var a = vector()
	return a[1]
end

local test = require("test")
test.eq(foo2(),12)
