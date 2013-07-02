

terra foo()
	return (1),(2)
end

terra bar()
	var c = [quote var a = 3 in a end]
	var d = 5
	[quote var b = -1 in c,d end] = c + 10,11
	([quote var b = -1 in c,d+1 end]) = c + 10
	return [quote var a = 3 in [quote var b = 4 in a + b + c + d end] end]
end

local a,b = foo()
assert(a == 1 and b == 2)
assert(41 == bar())