
local add = terralib.defaultoperator("+")
local addm = terralib.defaultmetamethod("__add")


terra foobar()
	return [add(`3,addm(`4,`5))]
end

assert(foobar() == 12)
