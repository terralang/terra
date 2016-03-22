


local r,e = xpcall(function()
	local struct A {
		a : opaque
	}
	local v = terralib.new(A)
end,debug.traceback)

assert(not r and e:match("attempting to use an opaque type"))


local r,e = xpcall(function()
	local v = terralib.new(opaque)
end,debug.traceback)

assert(not r and e:match("attempting to use an opaque type"))