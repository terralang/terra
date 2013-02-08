
local aligned = terralib.aligned
terra foobar(a : &float)
	aligned(@a,4) = aligned(a[3],4)
end

foobar:compile()
