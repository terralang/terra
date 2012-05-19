io.write("loading terra lib...")
_G.terra = {}

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
	return self.kind.." <todo: retrieve from file>"
end
function terra.tree:is(value)
	return self.kind == value
end
function terra.tree:printraw()
	local function header(t)
		if type(t) == "table" then
			return t["kind"] or ""
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
					print(prefix..header(v))
					if isList(v) then
						printElem(v,string.rep(" ",2+#spacing))
					else
						printElem(v,string.rep(" ",2+#prefix))
					end
				end
			end
		end
	end
	print(header(self))
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
	print("NYI - compile")
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
	local obj = { untypedtree = newtree, filename = newtree.filename, envfunction = env }
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
	local base_types = { ["bool"] = 1, 
	                     ["int8"] = 1, ["int16"] = 2, ["int32"] = 4, ["int64"] = 8,
	                     ["uint8"] = 1,["uint16"] = 2,["uint32"] = 4,["uint64"] = 8,
	                     ["float"] = 4, ["double"] = 8,
	                     ["void"] = 9 }
	types.type = {} --all types have this as their metatable
	types.type.__index = types.type
	
	function types.type:__tostring()
		return self.name
	end
	
	types.table = {}
	
	local function mktyp(v)
		return setmetatable(v,types.type)
	end
	
	types.error = mktyp { kind = "error", name = "error" } --object representing where the typechecker failed
	
	function types.pointer(typ)
		if typ == types.error then return types.error end
		
		local name = "&"..typ.name 
		local value = types.table[name]
		if value == nil then
			value = mktyp { kind = "pointer", typ = typ, name = name }
			types.table[name] = value
		end
		return value
	end
	function types.array(typ,sz)
		--TODO
	end
	function types.builtin(name)
		local t = types.table[name]
		if t then
			return t
		elseif base_types[name] == nil then
			return nil
		else
			types.table[name] = mktyp { kind = "builtin", name = name, size = base_types[name] }
			return types.table[name]
		end
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
	function types.functype(arguments,results)
		--TODO
	end
	
	
	for typ,_ in pairs(base_types) do
		--introduce builtin types into global namespace
		_G[typ] = types.builtin(typ) 
	end
	_G["int"] = int32
	_G["long"] = int64
	
	function types.istype(v)
		return getmetatable(v) == types.type
	end
	
	terra.types = types
end

function terra.resolveprimary(tree,env)
	
end
--takes an AST representing a type and returns a type object from the type table

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
		return terra.reporterror(ctx,t,msg,t)
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
			return err "unsupported expression in type: "
		end
	end
	if t:is "index" then
		return err "array types not implemented"
	elseif t:is "operator" then
		if t.operator ~= "&" then return err "unsupported operator on type: " end
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
"var"
"select"
"literal"
"constructor"
"index"
"method"
"apply"
"operator"


other:
"recfield"
"listfield"
"function"
"ifbranch" (done)

]]

terra.list = {} --used for all ast lists
setmetatable(terra.list,{ __index = table })
terra.list.__index = terra.list
function terra.newlist()
	return setmetatable({},terra.list)
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


function terra.func:typecheck()
	local ctx = { func = self }
	local ftree = ctx.func.untypedtree
	
	local function resolvetype(t)
		return terra.resolvetype(ctx,t)
	end
	
	-- 1. generate types for parameters, if return types exists generate a types for them as well
	local typed_parameters = terra.newlist()
	for _,v in ipairs(ftree.parameters) do
		local typ = resolvetype(v.type)
		typed_parameters:insert( v:copy({ type = typ }) )
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
	
	
	local labels = {} --map from label name to definition (or, if undefined to the first goto using that label)
	local loop_depth = 0
	
	local env = parameters_to_type
	local function enterblock()
		env = setmetatable({},{ __index = env })
	end
	local function leaveblock()
		env = getmetatable(env).__index
	end
	
	local checkexp,checkstmt
	checkexp = function(e)
		if e:is "literal" then
			return e:copy { type = terra.types.builtin(e.type) }
		end
		error("NYI - "..e.kind,2)
	end
	local function checkexptyp(re,target)
		local e = checkexp(re)
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
	checkstmt = function(s)
		if s:is "block" then
			enterblock()
			local r = s.statements:map(checkstmt)
			leaveblock()
			return s:copy {statements = r}
		elseif s:is "return" then
			local rstmt = s:copy { expressions = s.expressions:map(checkexp) }
			return_stmts:insert(rstmt)
			return rstmt
		elseif s:is "label" then
			labels[s.value] = s --replace value with label definition
			return s
		elseif s:is "goto" then
			labels[s.label] = labels[s.label] or s --only replace definition if not already defined
			return s 
		elseif s:is "break" then
			if loop_depth == 0 then
				terra.reporterror(ctx,s,"break found outside a loop")
			end
			return s
		elseif s:is "while" then
			return checkcondbranch(s)
		elseif s:is "if" then
			local br = s.branches:map(checkcondbranch)
			local els = s.orelse and checkstmt(s.orelse)
			return s:copy{ branches = br, orelse = els }
		elseif s:is "repeat" then
			enterblock() --we don't use block here because, unlike while loops, the condition needs to be checked in the scope of the loop
			local new_blk = s.body:copy { statements = s.body.statements:map(checkstmt) }
			local e = checkexptyp(s.condition,bool)
			leaveblock()
			return s:copy { body = new_blk, condition = e }
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
					r = checkexptyp(s.initializers[i],typ)
				else
					r = checkexp(s.initializers[i])
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
		end
		error("NYI - "..s.kind,2)
	end
	
	local result = checkstmt(ftree.body)
	for _,v in pairs(labels) do
		if v:is "goto" then
			terra.reporterror(ctx,v,"goto to undefined label")
		end
	end
	
	
	print("Typed Tree:")
	result:printraw()
	print("Return Stmts:")
	return_stmts:printraw()
	
	if ctx.func.filehandle then
		terra.closesourcefile(ctx.func.filehandle)
		ctx.func.filehandle = nil
	end
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