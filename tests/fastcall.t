
terra foo()
	return 1
end


assert(1 == foo())
assert(foo.fastcall == foo:getdefinitions()[1].ffiwrapper)
assert(1 == foo())


terra foo2()
	return 1,2
end

local a,b = foo2()
assert(a == 1 and b == 2)
assert(foo2.fastcall == foo2:getdefinitions()[1])
local a,b = foo2()
assert(a == 1 and b == 2)

terra foo(a : int)
end

assert(foo.fastcall == nil)