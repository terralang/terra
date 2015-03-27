if not require("fail") then return end
terra test5()
	var d = 1.f ^ 2.f
	var e = 3.75 ^ 2.0
	return (d == 1.f) and (e == 1.75)
end


local test = require("test")

test.eq(test5(),0)
