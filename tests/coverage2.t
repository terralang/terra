function failit(match,fn)
	local success,msg = pcall(fn)
	if success then
		error("failed to fail.",2)
	elseif not string.match(msg,match) then
		error("failed wrong: "..msg,2)
	end
end
local test = require("test")
local erd = "Errors reported during"

failit(erd,function()
local aglobal = 5
local terra foo()
	return [ (function() aglobal = 4; return 3 end)() ]
end
foo()
end)

A = terralib.types.newstruct()
A.entries:insert{ field = "a", type = int[2] }

A.metamethods.__abouttofreeze = function() error("NOPE") end

failit(erd,function()
	A:freeze()
end)
local terra foo()
	var a : int[2]
	return 3
end
foo:compile()
local a = 0
foo:compile(function()
	a = a + 1
end)
assert(a == 1)
--[[
async call when something is already compiled
recursive explicit compile call
compile call on errored function
overload call from lua failure
printstats
astype error
asvalue errors
struct has nontype entry
symbol in cstring
non-string/symbol field
badentry in struct layout
async already frozen
sync freezing
freeze an error
redefine struct
fail a user-defined cast
checkshift when b is vector but a is not
ifelse "expected a boolean or vector of booleans but found "
attempting to call a method on a nonstructural type
no such method defined
"expected a function or macro but found lua value of type "
macro that fails
typedexpression crosses functions

]]