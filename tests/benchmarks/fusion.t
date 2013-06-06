C = terralib.includecstring [[
	#include <stdio.h>
	#include <stdlib.h>
	#include <math.h>
	#ifndef _WIN32
	#include <sys/time.h>
	static double CurrentTimeInSeconds() {
	    struct timeval tv;
	    gettimeofday(&tv, NULL);
	    return tv.tv_sec + tv.tv_usec / 1000000.0;
	}
	#else
	#include <time.h>
	double CurrentTimeInSeconds() {
		return time(NULL);
	}
	#endif
]]
local vectorize = true
local optable = {}
local number = double
local VL = 2
local VT = vector(number,VL)
local VP = &VT --&number
local LT
if vectorize then
	LT = VP
else
	LT = &number
end

struct Array {
	N : int;
	data : &number;
}
Array.methods.new = terra(N : int)
	return Array { N = N, data = [&number](C.malloc(sizeof(number)*N)) }
end

local function addred(name,init,q)
	Array.methods[name] = terra(self : &Array)
		var r = number(init)
		for i = 0, self.N do
			var input = self.data[i];
			--C.printf("%f\n",input);
			[q(r,input)]
		end
		return r
	end
end

addred("sum",0.0,function(r,input)
	return quote
		r = r + input
	end
end)

addred("min",1000000000,function(r,input)
	return quote
		r = terralib.select(r < input,r,input)
	end
end)


local metamethodtable
local function MakeExpType(op,args)
	local struct ExpType {}
	setmetatable(ExpType.metamethods,metamethodtable)
	local info = {}
	info.op = op
	info.args = terralib.newlist{}
	for i,a in ipairs(args) do
		local typ = a:gettype()
		local thenode = optable[typ]
		if not thenode then
			info.args[i] = a
		else
			info.args[i] = thenode
		end
	end
	optable[ExpType] = info
	return ExpType
end

Array.methods.set = macro(function(self,exp)

	local formal = terralib.newlist()
	local actual = terralib.newlist()
	
	local function findargs(op)
		if terralib.isquote(op) then
			local sym = symbol(op:gettype())
			formal:insert(sym)
			actual:insert(op)
			return sym
		else
			return { op = op.op, args = op.args:map(findargs) }
		end
	end
	local typ = exp:gettype()
	local op = optable[typ]
	if not op then
		error("set must take an expression")
	end

	local newop = findargs(op)
	
	local i = symbol(int)

	local function emitExp(op)
		if terralib.issymbol(op) then
			if op.type == Array then
				return `@LT(&op.data[i])
			else 
				return `op
			end
		else
			local action = op.op
			local args = op.args:map(emitExp)
			return action(unpack(args))
		end
	end
	local sizeobj
	for i,a in ipairs(formal) do
		if a.type == Array then
			sizeobj = a
		end
	end

	local terra implementation(r : &Array, [formal])
		var size = [ sizeobj ].N
		for [i] = 0, size, [vectorize and VL or 1] do
			@LT(&r.data[i]) = [ emitExp(newop) ]
		end
	end
	--print("DISAS")
	--implementation:disas()
	--print("DONE")
	return `implementation(&self,[actual])
end)
metamethodtable = {
	__index = function(self,index)
		if index == "__cast" then
			return Materialize
		end
		local op = terralib.defaultmetamethod(index)
		return op and macro(function(...)
			local typ = MakeExpType(op,terralib.newlist {...})
			assert(typ)
			return `typ {}			
		end)
	end
}
Lift = function(op)
	local function opfn(arg)
		if vectorize then
			local terra liftimpl( a : VT ) : VT
				return vector(op(a[0]),op(a[1]))
				--return vector(op(a[0]),op(a[1]),op(a[2]),op(a[3]))
			end
			return `liftimpl(arg)
		else
			return `op(arg)
		end
	end
	return macro(function(...)
		local typ = MakeExpType(opfn,terralib.newlist{...})
		assert(typ)
		return `typ {}
	end)
end

LiftV = function(op)
	local function opfn(...)
		local args = terralib.newlist {...}
		return `op(args)
	end
	return macro(function(...)
		local typ = MakeExpType(opfn,terralib.newlist{...})
		assert(typ)
		return `typ {}
	end)
end

terra minS(a : vector(number,VL), b : vector(number,VL))
	return terralib.select(a < b,a,b)
end

minV = LiftV(minS)

setmetatable(Array.metamethods, metamethodtable)

terra foo(a : double)
	return a + 1
end

local Lfoo = Lift(C.sqrt)

terra doit(s : int)
	var a  = Array.new(10)
	for i = 0,10 do
		a.data[i] = s + i
	end
	var c,b  = Array.new(10), Array.new(10)
	b:set(a - 4 + minV(a,a+1) + Lfoo(a))
	c:set(b + a)
	for i = 0,10 do
		print(i,c.data[i])
	end
end

doit(0)

















