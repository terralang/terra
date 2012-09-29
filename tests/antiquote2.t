

function omgfunc()
	return 4
end

local what = `[ {2,3} ]
terra foo()
	return [{3,`[ {2,3} ]}]
end

local test = require("test")
a,b,c = foo()
test.eq(a,3)
test.eq(b,2)
test.eq(c,3)