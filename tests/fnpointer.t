
terra foo()
	return 4
end

terra bar()
	return 5
end

terra baz(a : int64)
	var afn = foo
	if a > 2 then
	   afn = bar
	end
	return afn()
end

local test = require("test")
test.eq(baz(1),4)
test.eq(baz(3),5)