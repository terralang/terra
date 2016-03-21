
local a = 0
terra bar :: {} -> int

local foo = macro(function(arg)
	assert(({} -> int) == &bar:gettype())
	a = 3
	return 3
end)

terra bar()
	return foo()
end

assert(bar() == 3)
assert(a == 3)