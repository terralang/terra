C = terralib.includecstring [[
	#include <stdio.h>
	#include <stdlib.h>
	#include <math.h>
	double CurrentTimeInSeconds() {
	  struct timeval tv;
	  gettimeofday(&tv, NULL);
	  return tv.tv_sec + tv.tv_usec / 1000000.0;
	}
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
	ref : int;
}
struct Expression {
	ref : int
}

Array.methods.new = terra(N : int)
	return Array { N = N, data = [&number](C.malloc(sizeof(number)*N)), ref = -1 }
end

local optable = terralib.newlist()
local instrs = terralib.newlist()
local function recordset(array, ref)
	print("REF = ",ref)
	local inst = instrs[ref]
	assert(inst.output == nil)
	inst.output = array
	array.ref = ref
end

local function recordop(result,opidx,...)
	local args = terralib.newlist()
	for i,a in ipairs({...}) do
		local obj = a[0]
		local typ = type(obj) == "cdata" and terralib.typeof(obj)
		if typ == Array then
			if obj.data == nil then
				args[i] = obj.ref
			else
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
	C.printf("ref = %d\n",exp.ref)
	recordset(self,exp.ref)
end
function Array.methods.free(self)
	if self.data == nil then
		instrs[self.ref].output = nil
	end
end
function Array.methods.flush(self)
	terralib.tree.printraw(instrs)
	local body = terralib.newlist()
	local outputs = terralib.newlist()
	local idx = symbol(int)
	local N
	local nodes = {}
	for i,inst in ipairs(instrs) do
		local rhs
		if inst.op == "load" then
			N = N or inst.N
			assert(N == inst.N)
			rhs = `inst.data[idx]
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
			body:insert(quote
				inst.output.data[idx] = [n]
			end)
			outputs:insert(quote
				inst.output.data = [&number](C.malloc(sizeof(number)*N))
				inst.output.N = N
			end)
		end
	end
	local terra codeblock()
		[outputs]
		for [idx] = 0,N do
			[body]
		end
	end
	codeblock:disas()
	codeblock()
end

metamethodtable = {
	__index = function(self,index)
		local op = terralib.defaultmetamethod(index)
		return op and macro(function(ctx,tree,...)
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
}
setmetatable(Array.metamethods,metamethodtable)
setmetatable(Expression.metamethods,metamethodtable)

terra doit()
	var a = Array.new(10)
	for i = 0,a.N do
		a.data[i] = i
	end
	var b : Array
	var c : Array
	b:set(a + a + a + 4)
	c:set(b + a + 3)
	b:flush()
	for i = 0,b.N do
		C.printf("%d %f %f\n",i,b.data[i],c.data[i])
	end
end
doit()
