io.write("loading terra lib...")

--[[
some experiments with ffi to call function given a function pointer
local ffi = require("ffi")
print("push function is: "..type(functest))
ffi.cdef("typedef struct { void (*fn)(double,double); } my_struct;") 
func = ffi.cast("my_struct*",functest)
func.fn(1,2)
]]

terra.tree = {} --metatype for trees
terra.tree.__index = terra.tree
function terra.tree:__tostring()
	return terra.kinds[self.kind].." <todo: retrieve from file>"
end
function terra.tree:is(value)
	return self.kind == terra.kinds[value]
end
 

function terra.tree:printraw()
	local function header(key,t)
		if type(t) == "table" then
			return terra.kinds[t["kind"]] or ""
		elseif (key == "type" or key == "operator") and type(t) == "number" then
			return terra.kinds[t] .. " (enum " .. tostring(t) .. ")"
		else
			return tostring(t)
		end
 	end
 	local function isList(t)
 		return type(t) == "table" and #t ~= 0
 	end
	local function printElem(t,spacing)
		if(type(t) == "table") then
			for k,v in pairs(t) do
				if k ~= "kind" and k ~= "offset" and k ~= "linenumber" then
					local prefix = spacing..k..": "
					print(prefix..header(k,v))
					if isList(v) then
						printElem(v,string.rep(" ",2+#spacing))
					else
						printElem(v,string.rep(" ",2+#prefix))
					end
				end
			end
		end
	end
	print(header(nil,self))
	if type(self) == "table" then
		printElem(self,"  ")
	end
end

function terra.tree:copy(new_tree)
	for k,v in pairs(self) do
		if not new_tree[k] then
			new_tree[k] = v
		end
	end
	return setmetatable(new_tree,getmetatable(self))
end
function terra.newtree(ref,body)
	body.offset = ref.offset
	body.linenumber = ref.linenumber
	return setmetatable(body,terra.tree)
end

function terra.istree(v) 
	return terra.tree == getmetatable(v)
end

terra.func = {} --metatable for all function types
terra.func.__index = terra.func
function terra.func:env()
	self.envtbl = self.envtbl or self.envfunction() --evaluate the environment if needed
	self.envfunction = nil --we don't need the closure anymore
	return self.envtbl
end
function terra.func:type()
	
end
function terra.func:compile()
	print("compiling function:")
    self.untypedtree:printraw()
	print("with local environment:")
	terra.tree.printraw(self:env())
	self.typedtree = self:typecheck()
	--now call llvm to compile...
	terra.compile(self)
end

function terra.func:__call(...)
	if not self.typedtree then
		self:compile()
	end
	print("NYI - invoke terra function")
end

function terra.newfunction(olddef,newtree,env)
	if olddef then
		error("NYI - overloaded functions",2)
	end
	local fname = newtree.filename:gsub("%.","_") .. newtree.offset --todo if a user writes terra foo, pass in the string "foo"
	local obj = { untypedtree = newtree, filename = newtree.filename, envfunction = env, name = fname }
	return setmetatable(obj,terra.func)
end

--[[
types take the form
builtin(name)
pointer(typ)
array(typ,N)
struct(types)
union(types)
named(name,typ), where typ is the unnamed structural type and name is the internally generated unique name for the type
functype(arguments,results) 
]]
do --construct type table that holds the singleton value representing each unique type
   --eventually this will be linked to the LLVM object representing the type
   --and any information about the operators defined on the type
	local types = {}
	
	
	types.type = {} --all types have this as their metatable
	types.type.__index = types.type
	
	function types.type:__tostring()
		return self.name
	end
	function types.type:isintegral()
		return self.kind == terra.kinds.builtin and self.type == terra.kinds.integer
	end
	function types.type:isarithmetic()
		return self.kind == terra.kinds.builtin and (self.type == terra.kinds.integer or self.type == terra.kinds.float)
	end
	function types.type:islogical()
		return self.kind == terra.kinds.builtin and self.type == terra.kinds.logical
	end
	function types.type:canbeord()
		return self:isintegral() or self:islogical()
	end
	function types.type:ispointer()
		return self.kind == terra.kinds.pointer
	end
	local function mktyp(v)
		return setmetatable(v,types.type)
	end
		
	function types.istype(v)
		return getmetatable(v) == types.type
	end
	
	types.table = {}
	
	--initialize integral types
	local integer_sizes = {1,2,4,8}
	for _,size in ipairs(integer_sizes) do
		for _,s in ipairs{true,false} do
			local name = "int"..tostring(size * 8)
			if not s then
				name = "u"..name
			end
			local typ = mktyp { kind = terra.kinds.builtin, bytes = size, type = terra.kinds.integer, signed = s, name = name}
			types.table[name] = typ
		end
	end  
	types.table["float"] = mktyp { kind = terra.kinds.builtin, bytes = 4, type = terra.kinds.float, name = "float" }
	types.table["double"] = mktyp { kind = terra.kinds.builtin, bytes = 8, type = terra.kinds.float, name = "double" }
	types.table["bool"] = mktyp { kind = terra.kinds.builtin, bytes = 1, type = terra.kinds.logical, name = "bool" }
	
	types.error = mktyp { kind = terra.kinds.error , name = "error" } --object representing where the typechecker failed
	
	function types.pointer(typ)
		if typ == types.error then return types.error end
		
		local name = "&"..typ.name 
		local value = types.table[name]
		if value == nil then
			value = mktyp { kind = terra.kinds.pointer, type = typ, name = name }
			types.table[name] = value
		end
		return value
	end
	function types.array(typ,sz)
		--TODO
	end
	function types.builtin(name)
		return types.table[name] or types.error
	end
	function types.struct(fieldnames,fieldtypes,listtypes)
		--TODO
	end
	function types.union(fieldnames,fieldtypes)
		--TODO
	end
	function types.named(typ)
		--TODO
	end
	function types.functype(parameters,returns)
		local function getname(t) return t.name end
		local a = parameters:map(getname):mkstring("{",",","}")
		local r = returns:map(getname):mkstring("{",",","}")
		local name = a.."->"..r
		local value = types.table[name]
		if value == nil then
			value = mktyp { kind = terra.kinds.functype, parameters = parameters, returns = returns, name = name }
		end
		return value
	end
	
	for name,typ in pairs(types.table) do
		--introduce builtin types into global namespace
		-- print("type ".. name)
		_G[name] = typ 
	end
	_G["int"] = int32
	_G["long"] = int64
	
	terra.types = types
end

--terra.printlocation
--and terra.opensourcefile are inserted by C wrapper
function terra.printsource(ctx,anchor)
	if not ctx.func.filehandle then
		ctx.func.filehandle = terra.opensourcefile(ctx.func.filename)
	end
	terra.printlocation(ctx.func.filehandle,anchor.offset)
end

function terra.reporterror(ctx,anchor,...)
	ctx.has_errors = true
	io.write(ctx.func.filename..":"..anchor.linenumber..": ")
	for _,v in ipairs({...}) do
		io.write(tostring(v))
	end
	io.write("\n")
	terra.printsource(ctx,anchor)
	return terra.types.error
end

function terra.resolvetype(ctx,t)
	local function err(msg)
		return terra.reporterror(ctx,t,msg)
	end
	local function check(t)
		if terra.types.istype(t) then
			return t 
		else 
			err "not a type: " 
		end
	end
	local function primary(t)
		if t:is "select" then
			local lhs = primary(t.value)
			return lhs and lhs[t.field]
		elseif t:is "var" then
			return ctx.func:env()[t.name]
		elseif t:is "literal" then
			return t
		else
			return err "unsupported expression in type"
		end
	end
	if t:is "index" then
		return err "array types not implemented"
	elseif t:is "operator" then
		if terra.kinds[t.operator] ~= "&" then return err "unsupported operator on type" end
		local value = terra.resolvetype(ctx,t.operands[1])
		return terra.types.pointer(value)
	else
		return check(primary(t))
	end
end
local function map(lst,fn)
	r = {}
	for i,v in ipairs(lst) do
		r[i] = fn(v)
	end
	return r
end
--[[
statements:

"assignment" (need convertible to, l-exp tracking)
"goto" (done)
"break" (done)
"label" (done)
"while" (done)
"repeat" (done)
"fornum" (need is numeric)
"forlist" (need to figure out how iterators will work...)
"block" (done)
"if" (done)
"defvar" (done - except for multi-return and that checkexp doesn't consider coersions yet)
"return" (done - except for final check)

expressions:
"var" (done)
"select" (done - except struct extract)
"literal" (done)
"constructor"
"index"
"method"
"apply"
"operator" (done - except pointer operators)


other:
"recfield"
"listfield"
"function"
"ifbranch" (done)

]]

terra.list = {} --used for all ast lists
setmetatable(terra.list,{ __index = table })
terra.list.__index = terra.list
function terra.newlist(lst)
	if lst == nil then
		lst = {}
	end
	return setmetatable(lst,terra.list)
end

function terra.list:map(fn)
	local l = terra.newlist()
	for i,v in ipairs(self) do
		l[i] = fn(v)
	end	
	return l
end
function terra.list:printraw()
	for i,v in ipairs(self) do
		if v.printraw then
			print(i,v:printraw())
		else
			print(i,v)
		end
	end
end
function terra.list:mkstring(begin,sep,finish)
	if sep == nil then
		begin,sep,finish = "",begin,""
	end
	local len = #self
	if len == 0 then return begin..finish end
	local str = begin .. tostring(self[1])
	for i = 2,len do
		str = str .. sep .. tostring(self[i])
	end
	return str..finish
end


function terra.func:typecheck()
	local ctx = { func = self }
	local ftree = ctx.func.untypedtree
	
	local function resolvetype(t)
		return terra.resolvetype(ctx,t)
	end
	
	local function insertcast(exp,typ)
		if typ == exp.type then
			return exp
		else
			--TODO: check that the cast is valid and insert the specific kind of cast 
			--so that codegen in llvm is easy
			return terra.newtree(exp, { kind = terra.kinds.cast, from = exp.type, to = typ, expression = exp })
		end
	end
	
	local function typematch(op,lstmt,rstmt)
		local function err()
			terra.reporterror(ctx,op,"incompatible types: ",lstmt.type," and ",rstmt.type)
		end
		
		local function castleft()
			return rstmt.type,insertcast(lstmt,rstmt.type),rstmt
		end
		local function castright()
			return lstmt.type,lstmt,insertcast(rstmt,lstmt.type) 
		end
		
		if lstmt.type == rstmt.type then return lstmt.type,lstmt,rstmt end
		if lstmt.type == terra.types.error or rstmt.type == terra.types.error then return terra.types.error,lstmt,rstmt end
		
		print(lstmt.type, rstmt.type)
		if lstmt.type.kind == terra.kinds.builtin and rstmt.type.kind == terra.kinds.builtin then
			if lstmt.type.type == terra.kinds.integer and rstmt.type.type == terra.kinds.integer then
				if lstmt.type.size < rstmt.type.size then
					return castleft()
				elseif lstmt.type.size > rstmt.type.size then
					return castright()
				elseif lstmt.type.signed then --signed versus unsigned
					return castleft()
				else
					return castright()
				end
			elseif lstmt.type.type == terra.kinds.integer and rstmt.type.type == terra.kinds.float then
				return castleft()
			elseif lstmt.type.type == terra.kinds.float and rstmt.type.type == terra.kinds.integer then
				return castright()
			elseif lstmt.type.type == terra.kinds.float and rstmt.type.type == terra.kinds.float then
				return double, insertcast(lstmt,double), insertcast(rstmt,double)
			else
				err()
				return terra.types.error,lstmt,rstmt
			end
		else
			err()
			return terra.types.error,lstmt,rstmt
		end
	end
	
	-- 1. generate types for parameters, if return types exists generate a types for them as well
	local typed_parameters = terra.newlist()
	local parameter_types = terra.newlist() --just the types, used to create the function type
	for _,v in ipairs(ftree.parameters) do
		local typ = resolvetype(v.type)
		typed_parameters:insert( v:copy({ type = typ }) )
		parameter_types:insert( typ )
		--print(v.name,parameters_to_type[v.name])
	end
	
	local return_stmts = terra.newlist() --keep track of return stms, these will be merged at the end, possibly inserting casts
	if ftree.return_types then
		return_stmts:insert({ type = ftree.return_types:map(resolvetype), stmt = nil })
	end
	
	local parameters_to_type = {}
	for _,v in ipairs(typed_parameters) do
		parameters_to_type[v.name] = v
	end
	
	
	local labels = {} --map from label name to definition (or, if undefined to the list of already seen gotos that target that label)
	
	local env = parameters_to_type
	local function enterblock()
		env = setmetatable({},{ __index = env })
	end
	local function leaveblock()
		env = getmetatable(env).__index
	end
	
	local loopstmts = terra.newlist()
	local function enterloop()
		local bt = {}
		loopstmts:insert(bt)
		return bt
	end
	local function leaveloop()
		loopstmts:remove()
	end
	
	local checkexp,checkstmt, checkexpraw, checkrvalue
	
	local function checkunary(ee,property)
		local e = checkrvalue(ee.operands[1])
		if e.type ~= terra.types.error and not e.type[property](e.type) then
			terra.reporterror(ctx,e,"argument of unary operator is not valid type but ",t)
			return e:copy { type = terra.types.error }
		end
		return ee:copy { type = e.type, operands = terra.newlist{e} }
	end	
	local function checkbinary(e,property)
		if #e.operands == 1 then
			return checkunary(e,property)
		end
		local t,l,r = typematch(e,checkrvalue(e.operands[1]),checkrvalue(e.operands[2]))
		if t ~= terra.types.error and not t[property](t) then
			terra.reporterror(ctx,e,"arguments of binary operators are not valid type but ",t)
			return e:copy { type = terra.types.error }
		end
		return e:copy { type = t, operands = terra.newlist {l,r} }
	end
	
	
	local function checkbinaryarith(e)
		return checkbinary(e,"isarithmetic")
	end

	local function checkintegralarith(e)
		return checkbinary(e,"isintegral")
	end
	local function checkcomparision(e)
		local t,l,r = typematch(e,checkrvalue(e.operands[1]),checkrvalue(e.operands[2]))
		return e:copy { type = bool, operands = terra.newlist {l,r} }
	end
	local function checklogicalorintegral(e)
		return checkbinary(e,"canbeord")
	end
	
	local function checklvalue(ee)
		local e = checkexp(ee)
		if not e.lvalue then
			terra.reporterror(ctx,e,"argument to operator must be an lvalue")
			e.type = terra.types.error
		end
		return e
	end
	local function checkaddressof(ee)
		local e = checklvalue(ee.operands[1])
		local ty = terra.types.pointer(e.type)
		return ee:copy { type = ty, operands = terra.newlist{e} }
	end
	local function checkdereference(ee)
		local e = checkrvalue(ee.operands[1])
		local ret = ee:copy { operands = terra.newlist{e}, lvalue = true }
		if not e.type:ispointer() then
			terra.reporterror(ctx,e,"argument of dereference is not a pointer type but ",e.type)
			ret.type = terra.types.error 
		else
			ret.type = e.type.type
		end
		return ret
	end
	local operator_table = {
		["-"] = checkbinaryarith;
		["+"] = checkbinaryarith;
		["*"] = checkbinaryarith;
		["/"] = checkbinaryarith;
		["%"] = checkbinaryarith;
		["<"] = checkcomparision;
		["<="] = checkcomparision;
		[">"] = checkcomparision;
		[">="] =  checkcomparision;
		["=="] = checkcomparision;
		["~="] = checkcomparision;
		["and"] = checklogicalorintegral;
		["or"] = checklogicalorintegral;
		["not"] = checklogicalorintegral;
		["&"] = checkaddressof;
		["@"] = checkdereference;
		["^"] = checkintegralarith;
	}
 
	function checkrvalue(e)
		local ee = checkexp(e)
		if ee.lvalue then
			return terra.newtree(e,{ kind = terra.kinds.ltor, type = ee.type, expression = ee })
		else
			return ee
		end
	end
	function checkexpraw(e) --can return raw lua objects, call checkexp to evaluate the expression and convert to terra literals
		if e:is "literal" then
			return e:copy { type = terra.types.builtin(e.type) }
		elseif e:is "var" then
			local v = env[e.name]
			if v ~= nil then
				return e:copy { type = v.type, definition = v, lvalue = true }
			end
			v = self:env()[e.name]  
			if v ~= nil then
				return v
			else
				terra.reporterror(ctx,e,"variable '"..e.name.."' not found")
				return e:copy { type = terra.types.error }
			end
		elseif e:is "select" then
			local v = checkexpraw(e.value)
			if terra.istree(v) then
				error("NYI - struct selection")
			else
				local v = type(v) == "table" and v[e.field]
				if v ~= nil then
					return v
				else
					terra.reporterror(ctx,e,"no field ",e.field," in object")
					return e:copy { type = terra.types.error }
				end
			end
		elseif e:is "operator" then
			local op_string = terra.kinds[e.operator]
			local op = operator_table[op_string]
			if op == nil then
				print(e.operator)
				terra.reporterror(ctx,e,"operator ",op_string," not defined in terra code.")
				return e:copy { type = terra.types.error }
			else
				return op(e)
			end
		end
		error("NYI - "..terra.kinds[e.kind],2)
	end
	function checkexp(ee)
		local e = checkexpraw(ee)
		if terra.istree(e) then
			return e
		elseif type(e) == "number" then
			return terra.newtree(ee, { kind = terra.kinds.literal, value = e, type = double })
		elseif type(e) == "boolean" then
			return terra.newtree(ee, { kind = terra.kinds.literal, value = e, type = bool })
		else 
			terra.reporterror(ctx,ee, "expected a terra expression but found "..type(e))
			return ee:copy { type = terra.types.error }
		end
	end
	
	local function checkexptyp(re,target)
		local e = checkrvalue(re)
		if e.type ~= target then
			terra.reporterror(ctx,e,"expected a ",target," expression but found ",e.type)
			e.type = terra.types.error
		end
		return e
	end
	local function checkcondbranch(s)
		local e = checkexptyp(s.condition,bool)
		local b = checkstmt(s.body)
		return s:copy {condition = e, body = b}
	end
	function checkstmt(s)
		if s:is "block" then
			enterblock()
			local r = s.statements:map(checkstmt)
			leaveblock()
			return s:copy {statements = r}
		elseif s:is "return" then
			local rstmt = s:copy { expressions = s.expressions:map(checkrvalue) }
			local rtypes = rstmt.expressions:map( function(exp)
				return exp.type
			end )
			return_stmts:insert( { type = rtypes, stmt = rstmt })
			return rstmt
		elseif s:is "label" then
			local lbls = labels[s.value] or terra.newlist()
			if terra.istree(lbls) then
				terra.reporterror(ctx,s,"label defined twice")
				terra.reporterror(ctx,lbls,"previous definition here")
			else
				for _,v in ipairs(lbls) do
					v.definition = s
				end
			end
			labels[s.value] = s
			return s
		elseif s:is "goto" then
			local lbls = labels[s.label] or terra.newlist()
			if terra.istree(lbls) then
				s.definition = lbls
			else
				lbls:insert(s)
			end
			labels[s.label] = lbls
			return s 
		elseif s:is "break" then
			local ss = s:copy({})
			if #loopstmts == 0 then
				terra.reporterror(ctx,s,"break found outside a loop")
			else
				ss.breaktable = loopstmts[#loopstmts]
			end
			return ss
		elseif s:is "while" then
			local breaktable = enterloop()
			local r = checkcondbranch(s)
			r.breaktable = breaktable
			leaveloop()
			return r
		elseif s:is "if" then
			local br = s.branches:map(checkcondbranch)
			local els = (s.orelse and checkstmt(s.orelse)) or terra.newtree(s, { kind = terra.kinds.block, statements = terra.newlist() })
			return s:copy{ branches = br, orelse = els }
		elseif s:is "repeat" then
			local breaktable = enterloop()
			enterblock() --we don't use block here because, unlike while loops, the condition needs to be checked in the scope of the loop
			local new_blk = s.body:copy { statements = s.body.statements:map(checkstmt) }
			local e = checkexptyp(s.condition,bool)
			leaveblock()
			leaveloop()
			return s:copy { body = new_blk, condition = e, breaktable = breaktable }
		elseif s:is "defvar" then
			if #s.variables ~= #s.initializers then
				error("NYI - multiple return values/uneven initializer lists")
			end
			local lhs = terra.newlist()
			local rhs = terra.newlist()
			for i,v in ipairs(s.variables) do
				local typ,r
				if v.type then 
					typ = resolvetype(v.type)
					r = insertcast(checkrvalue(s.initializers[i]),typ)
				else
					r = checkrvalue(s.initializers[i])
					typ = r.type
				end
				lhs:insert(v:copy { type = typ })
				rhs:insert(r)
			end
			--add the variables to current environment
			for i,v in ipairs(lhs) do
				env[v.name] = v
			end
			return s:copy { variables = lhs, initializers = rhs }
		elseif s:is "assignment" then
			if #s.lhs ~= #s.rhs then
				error("NYI - multiple return values")
			end
			local lhs = terra.newlist()
			local rhs = terra.newlist()
			for i,l in ipairs(s.lhs) do
				local ll = checklvalue(l)
				local rr = insertcast(checkrvalue(s.rhs[i]),ll.type)
				lhs:insert(ll)
				rhs:insert(rr)
			end
			return s:copy { lhs = lhs, rhs = rhs }
		else 
			return checkrvalue(s)
		end
		error("NYI - "..terra.kinds[s.kind],2)
	end
	
	local result = checkstmt(ftree.body)
	for _,v in pairs(labels) do
		if not terra.istree(v) then
			terra.reporterror(ctx,v[1],"goto to undefined label")
		end
	end
	
	
	print("Return Stmts:")
	
	local return_types
	if #return_stmts == 0 then
		return_types = terra.newlist()
	else 
		for _,stmt in ipairs(return_stmts) do
			if return_types == nil then
				return_types = stmt.type
			else
				if #return_types ~= #stmt.type then
					terra.reporterror(ctx,stmt.stmt,"returning a different length from previous return")
				else
					for i,v in ipairs(return_types) do 
						if v ~= stmt.type[i] then
							terra.reporterror(ctx,stmt.stmt, "returning type ",stmt.type[i], " but expecting ", v)
							error("NYI - type meet for return types")
						end
					end
				end
			end
		end
	end
	return_stmts:printraw()
	
	
	if ctx.func.filehandle then
		terra.closesourcefile(ctx.func.filehandle)
		ctx.func.filehandle = nil
	end
	
	
	local typedtree = ftree:copy { body = result, parameters = typed_parameters, labels = labels, type = terra.types.functype(parameter_types,return_types) }
	
	print("TypedTree")
	typedtree:printraw()
	
	if ctx.has_errors then
		error("Errors reported during compilation.")
	end
	
	return typedtree
	
	--[[
	
	2. register the parameter list as a variant of this function (ensure it is unique) and create table to hold the result of type checking
	3. initialize (variable -> type) map with parameter list and write enterblock, leave block functions
	4. initialize list of return statements used to determine the return type/check the marked return type was valid
	5. typecheck statement list, start with
	   -- arithmetic and logical operators on simple number types (no casting)
	   -- if and while statements
	   -- var statements (multiple cases)
	   -- assignment statements  (multiple cases)
	   -- return statements
	   -- literals
	   -- lua partial evaluation + lua numeric literals
	   next:
	   -- function calls (and recursive function compilation)
	   -- correct multiple return value in assignments
	   -- implicit arithmetic conversions
	   -- pointer types 
	   -- structured types
	   -- macros (no hygiene)
	   -- numeric for loop
	   -- iterator loop
	   make sure to track lvalues for all typed expressions
	]]
end
io.write("done\n")