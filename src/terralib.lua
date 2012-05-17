print ("loaded terra lib")
_G.terra = {}

terra.default = {} --default match value
terra.tree = {}
function terra.tree:match(tbl)
	fn = tbl[self.kind] or tbl[terra.default] or function() print("match error:"..self.kind) end
	fn(tbl)
end
terra._metatree = { __index = terra.tree } --used by parser when building AST

function terra.printElement(t) 
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
				if k ~= "kind" then
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
	print(header(t))
	if type(t) == "table" then
		printElem(t,"  ")
	end
end

function terra.newfunction(olddef,newvariant,env)
    print("previous object: "..tostring(olddef))
	terra.printElement(newvariant)
	print("local environment:")
	local e = env()
	terra.printElement(e)
	return newvariant
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
	types.metatype = {} --all types have this as their metatable
	types.table = {}
	
	function types.pointer(typ)
		local name = "&"..typ.name 
		local value = types.table[name]
		if value == nil then
			value = { kind = "pointer", typ = typ, name = name }
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
		elseif base_types[t] == nil then return nil
		else
			types.table[name] = { kind = "builtin", name = name, size = base_types[t] }
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
	
	terra.types = types
end

function terra.resolveprimary(tree,env)
	
end
--takes an AST representing a type and returns a type object from the type table
function terra.resolvetype(type_tree,env)
	local function primary(t)
		t:match {
			select = function() 
				local lhs = primary(t.value)
				return lhs and lhs[t.field] 
			end;
			var =  function() return env[t.name] end;
			literal = function() return t end;
			[terra.default] = function() return nil end;
		}
	end
	t:match {
		index = function() 
			--TODO: constuct array
			return nil
		end;
		operator = function() 
			if t.operator ~= "&" then return nil end
			local value = terra.resolvetype(t.operands[1],env)
			return value and terra.types.pointer(value)
		end;
	}
end