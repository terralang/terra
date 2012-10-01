
terra foo()
	return 1,2
end

local q = `foo()

terra bar()
	return q
end

a,b = bar()
local test = require("test")
test.eq(a,1)
test.eq(b,2)