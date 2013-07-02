

local a = 
quote
	var b = 1
in
	b + 0, b + 1
end

terra f0()
	return (a)
end
terra f1()
	return a
end
terra f2()
	a
end

assert(1 == f0())
local f10,f11 = f1()
assert(f10 == 1)
assert(f11 == 2)

local c = symbol()
local b = 
quote
	var [c]  = 3
in
	c,c+1
end

terra f3()
	b
	return ([c])
end
assert(f3() == 3)

a = global(1)
local emptyexp = quote
	a = a + 1
end

local emptystmts = quote
in 4,3
end

local both = quote
in 4,[quote a = a + 1 in 3 end]
end

terra bar(a : int,  b : int)
	return a + b
end
terra f4()
	return bar(emptystmts) + bar(1,2,emptyexp) + a
end

assert(f4() == 12)

terra f5()
	return bar(both,truncate(1,both)) + a
end

assert(f5() == 12)