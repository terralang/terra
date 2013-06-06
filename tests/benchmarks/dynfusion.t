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
	static double CurrentTimeInSeconds() {
		return time(NULL);
	}
	#endif
]]
local vectorize = true
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
	ref : int; --0 indicates it is materialized, -1 indicates uninitialized
}
struct Expression {
	ref : int
}


Array.methods.new = terra()
	return Array { N = 0, data = nil, ref = -1 }
end
Array.methods.alloc = terra(N : int)
	var self = Array.new()
	self.data = [&number](C.malloc(sizeof(number)*N))
	self.N = N
	self.ref = 0
	return self
end

local function addred(name,init,q)
	Array.methods[name] = terra(self : &Array)
		if self.ref ~= 0 then
			self:flush()
		end
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

addred("min",0.0,function(r,input)
	return quote
		r = terralib.select(r < input,r,input)
	end
end)

local optable = terralib.newlist()
local instrs = terralib.newlist()



function Array.methods.release(self)
	if self.ref > 0 then
		instrs[self.ref].output = nil
		self.ref = -1
	end
end

local function recordset(array, ref)
	Array.methods.release(array)
	local inst = instrs[ref]
	assert(inst.output == nil)
	inst.output = array
	array.ref = ref
	array.data = nil
	array.N = 0
end

local function recordop(result,opidx,...)
	local args = terralib.newlist()
	for i,a in ipairs({...}) do
		local obj = a[0]
		local typ = type(obj) == "cdata" and terralib.typeof(obj)
		if typ == Array then
			if obj.ref > 0 then
				args[i] = obj.ref
			else
				assert(obj.ref == 0)
				instrs:insert { op = "load", data = obj.data, N = obj.N }
				args[i] = #instrs
			end
		elseif typ == Expression then
			args[i] = obj.ref
		else
			instrs:insert { op = "loadc", constant = obj }
			args[i] = #instrs
		end
	end
	instrs:insert { op = opidx, args = args }
	result[0] = #instrs
end

terra Array:set(exp : Expression)
	recordset(self,exp.ref)
end


function Array.methods.flush(self)
	if self.ref == 0 then
		return
	end
	local begin = terralib.currenttimeinseconds()
	--terralib.tree.printraw(instrs)
	local body = terralib.newlist()
	local outputs = terralib.newlist()
	local idx = symbol(int)
	local N
	local nodes = {}
	for i,inst in ipairs(instrs) do
		local rhs
		if inst.op == "load" then
			N = N or inst.N
			--print(N,inst.N)
			assert(N == inst.N)
			rhs = `@VP(&inst.data[idx])
		elseif inst.op == "loadc" then
			rhs = inst.constant
		else 
			local theop = optable[inst.op]
			local theargs = inst.args:map(function(a) return `[ nodes[a] ] end)
			rhs = theop(unpack(theargs))
		end
		local n = symbol()
		nodes[i] = n
		body:insert(quote
			var [n] = rhs
		end)
		if inst.output then
			inst.output.ref = 0
			body:insert(quote
				@VP(&inst.output.data[idx]) = [n]
			end)
			if inst.output.data == nil then
				outputs:insert(quote
					inst.output.data = [&number](C.malloc(sizeof(number)*N))
					inst.output.N = N
				end)
			else
				assert(inst.output.N == N)
			end
		end
	end
	local terra codeblock()
		[outputs]
		for [idx] = 0,N,VL do
			[body]
		end
	end
	instrs = terralib.newlist()
	--codeblock:disas()
	
	codeblock:compile()
	local endcompile = terralib.currenttimeinseconds()
	codeblock()
	local endrun = terralib.currenttimeinseconds()

	print("compile: ",endcompile-begin,"run: ",endrun - endcompile, "total",endrun-begin)
	
end

local function createrecordforop(op)
	return macro(function(...)
		local args = terralib.newlist {...}
		optable:insert(op)
		local idx = #optable
		local formals = args:map(function(x) return symbol(x:gettype()) end)
		local recordargs = formals:map(function(x) return `&x end)
		local terra callrecord(opidx : int, [formals])
			var r : int
			recordop(&r,opidx,[recordargs])
			return Expression { r }
		end
		callrecord:disas()
		return `callrecord(idx,[args])
	end)
end

metamethodtable = {
	__index = function(self,index)
		local op = terralib.defaultmetamethod(index)
		return op and createrecordforop(op)
	end
}
setmetatable(Array.metamethods,metamethodtable)
setmetatable(Expression.metamethods,metamethodtable)

Lift = function(op)
	local function opfn(arg)
		if vectorize then
			local terra liftimpl( a : VT ) : VT
				return vector(op(a[0]),op(a[1]))
			end
			return `liftimpl(arg)
		else
			return `op(arg)
		end
	end
	return createrecordforop(opfn)
end

LiftV = function(op)
	local function opfn(...)
		local args = {...}
		return `op(args)
	end
	return createrecordforop(opfn)
end

terra minS(a : vector(number,VL), b : vector(number,VL))
	return terralib.select(a < b,a,b)
end

minV = LiftV(minS)

if true then
	local sqrt = Lift(C.sqrt)
	terra doit()
		var a,b,c = Array.alloc(16),Array.new(),Array.new()
		for i = 0,a.N do
			a.data[i] = i
		end
		b:set(a + a + a + 4)
		c:set(minV(b + a + 3,20))
		b:set(sqrt(b))
		b:flush()
		b:flush()
		for i = 0,b.N do
			C.printf("%d %f %f\n",i,b.data[i],c.data[i])
		end
		C.printf("AFTER2\n")
		C.printf("B = %d\n",b.ref)
	end
	doit:disas()
	doit()
end