var b = a + 1
var a = 3

terra foo()
	return b
end

local test = require("test")
test.eq(foo(),4)