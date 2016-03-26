local a = `-1.5

assert(a:asvalue() == -1.5)

function failit(match,fn)
	local success,msg = xpcall(fn,debug.traceback)
	if success then
		error("failed to fail.",2)
	elseif not string.match(msg,match) then
		error("failed wrong: "..msg,2)
	end
end

failit("expected a function pointer",function()
local terra foo :: int
end)

failit("expected a type but found",function()
tuple(1,2)
end)

failit("expected a label but found",function()

terra foo()
    :: [ "string" ] ::
end
end)

failit("call to overloaded function does not apply to any arguments",
function()
local a = terralib.overloadedfunction("a")
a:adddefinition(terra() end)
a:adddefinition(terra(a : int) end)
terra foo()
    a(2,3)
end
end)

failit("attempting to call overloaded",
function()
local a = terralib.overloadedfunction("a")
terra foo()
    a(2,3)
end
end)

failit("no such method",
function()
struct A {}

terra what(a : A)
    return A.foo()
end
end)

terra foo()
    terralib.debuginfo("what",3)
end

failit("expected a single iteration",
function()
terra what()
    for [{symbol(int),symbol(int)}] = 1,3 do
    end
end
end)