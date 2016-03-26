function failit(match,fn)
	local success,msg = xpcall(fn,debug.traceback)
	if success then
		error("failed to fail.",2)
	elseif not string.match(msg,match) then
		error("failed wrong: "..msg,2)
	end
end
local test = require("test")
local erd = "Errors reported during"

local terra f1 :: {} -> {}

failit(erd,function()
terra f1()
	return test
end
end)
failit("not defined",function()
f1:compile()
end)
failit("not defined",function()
	local terra foo()
		f1()
	end
	foo()
end)


local struct A {
	a : int
}

A.metamethods.__getentries = function(self)
	error("I AM BAD")
end

failit("__getentries",function()
	A:complete()
end)

failit("layout failed",function()
	local terra foo()
		var a : A
	end
	foo()
end)
