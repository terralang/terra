
local self = 1
local Rt = 1
local i = 1
local j = 1

local r,e = terralib.loadstring[[
	
	terra foo()
		var a = { [&double](4) = 3 }
	end
]]

assert(r == nil and e:match("unexpected symbol near '='"))

terra foo()
	var a = { [""] = 3 }
end

local s,l = symbol(int),label()

local function getsym()
	return s
end
local function getlbl() return l end
terra foo2()
	var [getsym()] = 3
	var a = { [getlbl()] = 4, _1 = [getsym()] }
	return a.[getlbl()] + a._1
end

assert(7 == foo2())

