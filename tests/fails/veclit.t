if not require("fail") then return end

terra foo()
	var a = 2* vector(1,"what",3)
	return a[0] + a[1] + a[2]
end

local test = require("test")
test.eq(foo(),12)
