

a = {}
var a.b, a.c : double = 3,4
local var d = 5
--print(a.b)

--a.b:gettype(nil)

terra bar()
	a.b = a.b + 1
	a.c = a.c + 1
	d = d + 1
end
terra foo()
	return a.b,a.c,d
end


local test = require("test")

bar()
i,j,k = foo()

test.eq(i,4)
test.eq(j,5)
test.eq(k,6)