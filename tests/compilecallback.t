
local a = 0
local foo = macro(function(arg)
	bar:compile(function()
		a = bar()
	end)
	a = 1
	return 3
end)

terra bar()
	return foo()
end

assert(bar() == 3)
assert(a == 3)
