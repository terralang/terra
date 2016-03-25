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

failit("cannot define global",function()
local aglobal = 5
local terra foo()
	return [ (function() aglobal = 4; return 3 end)() ]
end
foo()
end)

A = terralib.types.newstruct()
A.entries:insert{ field = "a", type = int[2] }

A.metamethods.__getentries = function() error("NOPE") end

failit(erd,function()
	A:complete()
end)
local terra foo()
	var a : int[2]
	return 3
end
foo:compile()

local terra errored :: int -> int
failit(erd,function()
	terra errored()
		return A
	end
	errored:compile()
end)
failit("not defined",function()
	errored()
end)

local terra ol1(a : int) return a end
local terra ol2(a : int, b : int) return a + b end

assert(ol1(3) == 3)
assert(ol2(3,4) == 7)

--ol:printstats()
NSE = terralib.types.newstruct()

failit("expected either a field type pair",function()
	NSE.entries:insert { field = "a", type = "b" }
	NSE:complete()
end)

SICS = terralib.types.newstruct()
SICS.entries:insert { field = label(), type = int }
a = 1
SICS.metamethods.__staticinitialize = function() a = a + 1 end
--print(terralib.new(SICS,{3}))

NSF = terralib.types.newstruct()
NSF.entries:insert { type = int , field = 3 }

failit("expected either a field type pair",function()
	NSF:complete()
end)
SICS:complete()
assert(a == 2)
struct SF {
	a : SF2
} 
struct SF2 {
	a : int
}
SF2.metamethods.__getentries = function(self) SF:complete() end
failit("type recursively contains itself",function()
SF:complete()
end)
failit("type recursively contains itself",function()
SF:complete()
end)

local oldSF = SF
	struct SF { b : int }

assert(oldSF ~= SF)
SF = oldSF

struct C {
	a : int
}

C.metamethods.__cast = function() return error("CAST ERROR") end

local terra casttest :: {} -> int
failit(erd,function()
local terra casttest()
	return int(C { 3 })
end
casttest()
end)

local terra shiftcheck()
	var r = 1 << vector(1,2,3,4)
	var r2 = vector(1,2,3,4) << 1
	return r[0],r[1],r[2],r[3],r2[0],r2[1],r2[2],r2[3]
end

test.meq({2,4,8,16,2,4,6,8},shiftcheck())

failit(erd,function()
	local terra foo()
		return terralib.select(3,4,5)
	end
	foo()
end)
failit(erd,function()
	local terra foo()
		return (4):foo()
	end
	foo()
end)
failit(erd,function()
	local terra foo()
		return (C {3}):foo()
	end
	foo()
end)
failit(erd,function()
	local a = { a = 4}
	local terra foo()
		return a()
	end
	foo()
end)
local saveit
local foom = macro(function(arg) saveit = arg; arg:astype();  end)
failit(erd,function()
	local terra foo(a : int)
		return foom(a)
	end
	foo()
end)

failit(erd,function()
	local terra foo()
		return saveit
	end
	foo:disas()
	foo()
end)
failit("lua expression is not a terra type but number",function()
	local struct A {
		a : 3
	}
end)

failit(erd,function()
	local terra foo :: {} -> {}
	local bar = macro(function() foo:compile() end)
	terra foo()
		return bar()
	end
	foo()
end)

struct ATF {
	a : int
}

ATF.metamethods.__getentries = function(self) 
	local terra foo()
		var a : ATF
		return a.a
	end
	foo:compile()
end

failit(erd,function()
	ATF:complete()
end)

struct FA {
	a : &FA2
}
struct FA2 {
	a : int
}

FA.metamethods.__staticinitialize = function() a = a + 1 end

FA2.metamethods.__staticinitialize = function(self)
	FA:complete()
end

FA:complete()

assert(a == 3)
--[[
freezing asynchronus needs to be called
]]