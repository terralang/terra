io.write("loading terra lib...")

--[[
some experiments with ffi to call function given a function pointer
local ffi = require("ffi")
print("push function is: "..type(functest))
ffi.cdef("typedef struct { void (*fn)(double,double); } my_struct;") 
func = ffi.cast("my_struct*",functest)
func.fn(1,2)
]]
local ffi = require("ffi")

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
 	local parents = {}
 	local depth = 0
	local function printElem(t,spacing)
		if(type(t) == "table") then
			if parents[t] then
				print(#spacing,"<cyclic reference>")
				return
			elseif depth > 0 and terra.isfunction(t) then
				return --don't print the entire nested function...
			end
			parents[t] = true
			depth = depth + 1
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
			depth = depth - 1
			parents[t] = nil
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
function terra.func:gettype(ctx)
	if self.type then --already typechecked
		return self.type
	else --we need to compile the function now because it has been referenced
		if self.iscompiling then
			if self.untypedtree.return_types then --we are already compiling this function, but the return types are listed, so we can resolve the type anyway	
				local params = terra.newlist()
				local function rt(t) return terra.resolvetype(ctx,t) end
				for _,v in ipairs(self.untypedtree.parameters) do
					params:insert(rt(v.type))
				end
				local rets = self.untypedtree.return_types:map(rt)
				self.type = terra.types.functype(params,rets) --for future calls
				return self.type
			else
				terra.reporterror(ctx,self.untypedtree,"recursively called function needs an explicit return type")
				return terra.types.error
			end
		else
			self:compile(ctx)
			return self.type
		end
	end
	
end
function terra.func:makewrapper()
	local fntyp = self.typedtree.type
	
	local rt
	local rname
	if #fntyp.returns == 0 then
		rt = "void"
	elseif #fntyp.returns == 1 then
		rt = fntyp.returns[1]:cstring()
	else
		local rtype = "typedef struct { "
		for i,v in ipairs(fntyp.returns) do
			rtype = rtype..v:cstring().." v"..tostring(i).."; "
		end
		rname = self.name.."_return_t"
		self.ffireturnname = rname.."[1]"
		rtype = rtype .. " } "..rname..";"
		print(rtype)
		ffi.cdef(rtype)
		rt = "void"
	end
	local function getcstring(t)
		return t:cstring()
	end
	local pa = fntyp.parameters:map(getcstring)
	
	if #fntyp.returns > 1 then
		pa:insert(1,rname .. "*")
	end
	
	pa = pa:mkstring("(",",",")")
	local ntyp = self.name.."_t"
	local cdef = "typedef struct { "..rt.." (*fn)"..pa.."; } "..ntyp..";"
	print(cdef)
	ffi.cdef(cdef)
	self.ffiwrapper = ffi.cast(ntyp.."*",self.fptr)
end

function terra.func:compile(ctx)
	ctx = ctx or {} -- if this is a top level compile, create a new compilation context
	print("compiling function:")
    self.untypedtree:printraw()
	print("with local environment:")
	terra.tree.printraw(self:env())
	self.typedtree = self:typecheck(ctx)
	self.type = self.typedtree.type
    
	if ctx.has_errors then 
		if ctx.func == nil then --if this was not the top level compile we let type-checking of other functions continue, 
		                        --though we don't actually compile because of the errors
			error("Errors reported during compilation.")
		end
	else 
		--now call llvm to compile...
		terra.compile(self)
		self:makewrapper()
	end
end

function terra.func:__call(...)
	if not self.typedtree then
		self:compile()
	end
	
    --TODO: generate code to do this for each function rather than interpret it on every call
    local nr = #self.typedtree.type.returns
    if nr > 1 then
    	local result = ffi.new(self.ffireturnname)
        self.ffiwrapper.fn(result,...)
        local rv = result[0]
        local rs = {}
        for i = 1,nr do
            table.insert(rs,rv["v"..i])
        end
        return unpack(rs)
    else
        return self.ffiwrapper.fn(...)
    end
end

do 
    local name_count = 0
    function terra.newfunction(olddef,newtree,name,env)
        if olddef then
            error("NYI - overloaded functions",2)
        end
        local rawname = (name or newtree.filename.."_"..newtree.linenumber.."_")
        local fname = rawname:gsub("[^A-Za-z0-9]","_") .. name_count --todo if a user writes terra foo, pass in the string "foo"
        name_count = name_count + 1
        local obj = { untypedtree = newtree, filename = newtree.filename, envfunction = env, name = fname }
        return setmetatable(obj,terra.func)
    end
end

function terra.isfunction(obj)
	return getmetatable(obj) == terra.func
end

--[[
types take the form
primitive(name)
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
	function types.type:isprimitive()
		return self.kind == terra.kinds.primitive
	end
	function types.type:isintegral()
		return self.kind == terra.kinds.primitive and self.type == terra.kinds.integer
	end
	function types.type:isfloat()
		return self.kind == terra.kinds.primitive and self.type == terra.kinds.float
	end
	function types.type:isarithmetic()
		return self.kind == terra.kinds.primitive and (self.type == terra.kinds.integer or self.type == terra.kinds.float)
	end
	function types.type:islogical()
		return self.kind == terra.kinds.primitive and self.type == terra.kinds.logical
	end
	function types.type:canbeord()
		return self:isintegral() or self:islogical()
	end
	function types.type:ispointer()
		return self.kind == terra.kinds.pointer
	end
	function types.type:isfunction()
		return self.kind == terra.kinds.functype
	end
	function types.type:cstring()
		if self:isintegral() then
			return tostring(self).."_t"
		elseif self:isfloat() then
			return tostring(self)
		elseif self:ispointer() then
			return self.type:cstring().."*"
		elseif self:islogical() then
			return "unsigned char"
		else
			error("NYI - cstring")
		end
	end
	
	--map from unique type identifier string to the metadata for the type
	types.table = {}
	
	--map from object that holds the table of methods to the internal object that holds the information about the type
	types.methodtabletotype = {}
	
	local function mktyp(v)
		v.methods = {} --create new blank method table
		types.methodtabletotype[v.methods] = v --associate this method table with this type
		return setmetatable(v,types.type)
	end
	
	function types.astype(v)
		return types.methodtabletotype[v] --if v is not a type, then this returns nil
	end
	
	--initialize integral types
	local integer_sizes = {1,2,4,8}
	for _,size in ipairs(integer_sizes) do
		for _,s in ipairs{true,false} do
			local name = "int"..tostring(size * 8)
			if not s then
				name = "u"..name
			end
			local typ = mktyp { kind = terra.kinds.primitive, bytes = size, type = terra.kinds.integer, signed = s, name = name}
			types.table[name] = typ
		end
	end  
	
	types.table["float"] = mktyp { kind = terra.kinds.primitive, bytes = 4, type = terra.kinds.float, name = "float" }
	types.table["double"] = mktyp { kind = terra.kinds.primitive, bytes = 8, type = terra.kinds.float, name = "double" }
	types.table["bool"] = mktyp { kind = terra.kinds.primitive, bytes = 1, type = terra.kinds.logical, name = "bool" }
	
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
	function types.primitive(name)
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
		--introduce primitive types into global namespace
		-- outside of the typechecker and internal terra modules
		-- types are represented by their unique method table
		-- which is why we assign the name to typ.methods not typ
		-- print("type ".. name)
		_G[name] = typ.methods 
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
		local typ = terra.types.astype(t)
		return typ or err "not a type: " 
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


function terra.func:typecheck(ctx)
	
	local oldfunc = ctx.func --save old function and set the current compiling function to this one
	ctx.func = self
	self.iscompiling = true --to catch recursive compilation calls
	
	local ftree = ctx.func.untypedtree
	
	local function resolvetype(t)
		return terra.resolvetype(ctx,t)
	end
	
	local function insertcast(exp,typ)
		if typ == exp.type or typ == terra.types.error or exp.type == terra.types.error then
			return exp
		else
			--TODO: check that the cast is valid and insert the specific kind of cast 
			--so that codegen in llvm is easy
			if not typ:isprimitive() or not exp.type:isprimitive() or typ:islogical() or exp.type:islogical() then
				terra.reporterror(ctx,exp,"invalid conversion from ",exp.type," to ",typ)
            end
			return terra.newtree(exp, { kind = terra.kinds.cast, from = exp.type, to = typ, type = typ, expression = exp })
		end
	end
	
	local function typemeet(op,a,b)
		local function err()
			terra.reporterror(ctx,op,"incompatible types: ",a," and ",b)
		end
		if a == terra.types.error or b == terra.types.error then
			return terra.types.error
		elseif a == b then
			return a
		elseif a.kind == terra.kinds.primitive and b.kind == terra.kinds.primitive then
			if a:isintegral() and b:isintegral() then
				if a.bytes < b.bytes then
					return b
				elseif b.bytes > a.bytes then
					return a
				elseif a.signed then
					return b
				else --a is unsigned but b is signed
					return a
				end
			elseif a:isintegral() and b:isfloat() then
				return b
			elseif a:isfloat() and b:isintegral() then
				return a
			elseif a:isfloat() and b:isfloat() then
				return terra.types.astype(double)
			end
		else
			err()
			return terra.types.error
		end
	end
	local function typematch(op,lstmt,rstmt)
		local inputtype = typemeet(op,lstmt.type,rstmt.type)
		return inputtype, insertcast(lstmt,inputtype), insertcast(rstmt,inputtype)
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
		return e:copy { type = terra.types.astype(bool), operands = terra.newlist {l,r} }
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
	
	
	local checkparameterlist, checkcall
	function checkparameterlist(anchor,params)
		local exps = terra.newlist()
		for i = 1,#params - 1 do
			exps:insert(checkrvalue(params[i]))
		end
		local minsize = #exps
		local multiret = nil
		
		if #params ~= 0 then --handle the case where the last value returns multiple things
			minsize = minsize + 1
			local last = params[#params]
			if last.kind == terra.kinds.apply or last.kind == terra.kinds.method then
				local multifunc = checkcall(last,true) --must return at least one value
				if #multifunc.types == 1 then
					exps:insert(multifunc) --just insert it as a normal single-return function
				else --remember the multireturn function and insert extract nodes into the expsresion list
					multiret = multifunc
					multiret.result = {} --table to link this result with extractors
					for i,t in ipairs(multifunc.types) do
						exps:insert(terra.newtree(multiret,{ kind = terra.kinds.extractreturn, index = (i-1), result = multiret.result, type = t}))
					end
				end
			else
				exps:insert(checkrvalue(last))
			end
		end
		
		local maxsize = #exps
		return terra.newtree(anchor, { kind = terra.kinds.parameterlist, parameters = exps, minsize = minsize, maxsize = maxsize, call = multiret })
	end
	local function insertcasts(typelist,paramlist) --typelist is a list of target types (or the value 'false'), paramlist is a parameter list that might have a multiple return value at the end
		if #typelist > paramlist.maxsize then
			terra.reporterror(ctx,paramlist,"expected at least "..#typelist.." parameters, but found only "..paramlist.maxsize)
		elseif #typelist < paramlist.minsize then
			terra.reporterror(ctx,paramlist,"expected no more than "..#typelist.." parameters, but found at least "..paramlist.minsize)
		end
		for i,typ in ipairs(typelist) do
			if typ and i <= paramlist.maxsize then
				paramlist.parameters[i] = insertcast(paramlist.parameters[i],typ)
			end
		end
        paramlist.size = #typelist
	end
	function checkcall(exp, mustreturnatleast1)
		local raw = checkexpraw(exp.value)
		if terra.isfunction(raw) then
			local fntyp = raw:gettype(ctx)
			local paramlist = checkparameterlist(exp,exp.arguments)
			insertcasts(fntyp.parameters,paramlist)
			
			local typ
			if #fntyp.returns >= 1 then
				typ = fntyp.returns[1]
			elseif mustreturnatleast1 then
				terra.reporterror(ctx,exp,"expected call to return at least 1 value")
				typ = terra.types.error
			end --otherwise this is used in statement context and does not require a type
			
			return exp:copy { arguments = paramlist,  value = raw, type = typ, types = fntyp.returns }
		else
			error("NYI - check call on non-literal function calls")
		end
	end
	
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
			return e:copy { type = terra.types.primitive(e.type) }
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
		elseif e:is "identity" then --simply a passthrough
			local e = checkexpraw(e.value)
			if terra.istree(e) then
				return e:copy { type = e.type, value = e }
			else
				return e
			end
		elseif e:is "apply" then
			return checkcall(e,true)
		end
		error("NYI - expression "..terra.kinds[e.kind],2)
	end
	function checkexp(ee)
		local e = checkexpraw(ee)
		if terra.istree(e) then
			return e
		elseif type(e) == "number" then
			return terra.newtree(ee, { kind = terra.kinds.literal, value = e, type = terra.types.astype(double) })
		elseif type(e) == "boolean" then
			return terra.newtree(ee, { kind = terra.kinds.literal, value = e, type = terra.types.astype(bool) })
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
		local e = checkexptyp(s.condition,terra.types.astype(bool))
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
			local rstmt = s:copy { expressions = checkparameterlist(s,s.expressions) }
			return_stmts:insert( rstmt )
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
			local e = checkexptyp(s.condition,terra.types.astype(bool))
			leaveblock()
			leaveloop()
			return s:copy { body = new_blk, condition = e, breaktable = breaktable }
		elseif s:is "defvar" then
			local lhs = terra.newlist()
			local res
			if s.initializers then
				local params = checkparameterlist(s,s.initializers)
				
				local vtypes = terra.newlist()
				for i,v in ipairs(s.variables) do
					local typ = false
					if v.type then
						typ = resolvetype(v.type)
					end
					vtypes:insert(typ)
				end
				
				insertcasts(vtypes,params)
				
				for i,v in ipairs(s.variables) do
					lhs:insert(v:copy { type = (params.parameters[i] and params.parameters[i].type) or terra.types.error }) 
				end
				
				res = s:copy { variables = lhs, initializers = params }
			else
				for i,v in ipairs(s.variables) do
					local typ = terra.types.error
					if not v.type then
						terra.reporterror(ctx,v,"type must be specified for unitialized variables")
					else
						typ = resolvetype(v.type)
					end
					lhs:insert(v:copy { type = typ })
				end
				res = s:copy { variables = lhs }
			end		
			--add the variables to current environment
			for i,v in ipairs(lhs) do
				env[v.name] = v
			end	
			return res
		elseif s:is "assignment" then
			
			local params = checkparameterlist(s,s.rhs)
			
			local lhs = terra.newlist()
			local vtypes = terra.newlist()
			for i,l in ipairs(s.lhs) do
				local ll = checklvalue(l)
				vtypes:insert(ll.type)
				lhs:insert(ll)
			end
			
			insertcasts(vtypes,params)
			
			return s:copy { lhs = lhs, rhs = params }
		elseif s:is "fornum" then
            function mkdefs(...)
                local lst = terra.newlist()
                for i,v in pairs({...}) do
                    lst:insert( terra.newtree(s,{ kind = terra.kinds.entry, name = v }) )
                end
                return lst
            end
            
            function mkvar(a)
                return terra.newtree(s,{ kind = terra.kinds["var"], name = a })
            end
            
            function mkop(op,a,b)
               return terra.newtree(s, {
                kind = terra.kinds.operator;
                operator = terra.kinds[op];
                operands = terra.newlist { mkvar(a), mkvar(b) };
                })
            end

            local dv = terra.newtree(s, { 
                kind = terra.kinds.defvar;
                variables = mkdefs(s.varname,"<limit>","<step>");
                initializers = terra.newlist({s.initial,s.limit,s.step})
            })
            
            local lt = mkop("<",s.varname,"<limit>")
            
            local newstmts = terra.newlist()
            for _,v in pairs(s.body.statements) do
                newstmts:insert(v)
            end
            
            local p1 = mkop("+",s.varname,"<step>")
            local as = terra.newtree(s, {
                kind = terra.kinds.assignment;
                lhs = terra.newlist({mkvar(s.varname)});
                rhs = terra.newlist({p1});
            })
            
            
            newstmts:insert(as)
            
            local nbody = terra.newtree(s, {
                kind = terra.kinds.block;
                statements = newstmts;
            })
            
            local wh = terra.newtree(s, {
                kind = terra.kinds["while"];
                condition = lt;
                body = nbody;
            })
        
            local desugared = terra.newtree(s, { kind = terra.kinds.block, statements = terra.newlist {dv,wh} } )
            desugared:printraw()
            return checkstmt(desugared)
		elseif s:is "apply" then
			return checkcall(s,false) --allowed to be void
		elseif s:is "method" then
			error ("NYI - methods")
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
	if ftree.return_types then --take the return types to be as specified
		return_types = ftree.return_types:map(resolvetype)
	else --calculate the meet of all return type to calculate the actual return type
		if #return_stmts == 0 then
			return_types = terra.newlist()
		else
			local minsize,maxsize
			for _,stmt in ipairs(return_stmts) do
				if return_types == nil then
					return_types = terra.newlist()
					for i,exp in ipairs(stmt.expressions.parameters) do
						return_types[i] = exp.type
					end
					minsize = stmt.expressions.minsize
					maxsize = stmt.expressions.maxsize
				else
					minsize = math.max(minsize,stmt.expressions.minsize)
					maxsize = math.min(maxsize,stmt.expressions.maxsize)
					if minsize > maxsize then
						terra.reporterror(ctx,stmt,"returning a different length from previous return")
					else
						for i,exp in ipairs(stmt.expressions) do
							if i <= maxsize then
								return_types[i] = typemeet(exp,return_types[i],exp.type)
							end
						end
					end
				end
			end
			while #return_types > maxsize do
				table.remove(return_types)
			end
			
		end
	end
	
	--now cast each return expression to the expected return type
	for _,stmt in ipairs(return_stmts) do
		insertcasts(return_types,stmt.expressions)
	end
	
	if ctx.func.filehandle then
		terra.closesourcefile(ctx.func.filehandle)
		ctx.func.filehandle = nil
	end
	
	
	local typedtree = ftree:copy { body = result, parameters = typed_parameters, labels = labels, type = terra.types.functype(parameter_types,return_types) }
	
	print("TypedTree")
	typedtree:printraw()
	
	ctx.func = oldfunc
	self.iscompiling = nil
	return typedtree
	
	--[[
	
	2. register the parameter list as a variant of this function (ensure it is unique) and create table to hold the result of type checking
	5. typecheck statement list, start with (done)
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
       
handling multi-returns:
checkparameterlist function:
         checks a list of expressions where the last one may be a function call with multiple returns
         generates an object that has the list of typed (single value) expressions, and
         an optional multi-valued (2+ values) return function (single value returns can go in expression list)
         the return values from the multi-function are placed in a (seperate?) list with a type, a reference to the
         function call that generated them and then their index into the argument list
         
         function calls found during a checkexp will just return their first (if any) value, or a special void type that cannot
         be cast/operated on by anything else
         
         codegen will need to handle two cases:
         1. function truncated to 0 or 1 and return value (NULL if 0)
         2. multi-return function (2+ arguments) return pointer to structure holding the return values
	]]
end
io.write("done\n")