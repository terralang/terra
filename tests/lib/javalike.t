local std = terralib.includec("stdlib.h")
local Class = {}
local metadata = {}
--map from class type to metadata about it:
-- parent = the type of the parent class or nil
-- methodimpl = methodname-funcdef table of the concrete implementations for this class
-- vtable = the type of the types vtable
-- vtableglobal = the global variable that holds the data for this vtable

local interfacemetadata = {}
--map from interface type to metadata about it

local vtablesym = symbol()

local function offsetinbytesfn(structtype,key)
    local terra offsetcalc() : uint64
        var a : &structtype = [&structtype](0)
        return [&uint8](&a.[key]) - [&uint8](a)
    end
    return offsetcalc
end

local function finalizelayout(self)
	local md = metadata[self]

	
	md.vtable = terralib.types.newstruct()
	md.methodimpl = {}

	self.entries:insert(1, { field = vtablesym, type = &md.vtable })

	local parentinterfaces
	if md.parent then
		md.parent:finalizelayout()
		local pmd = metadata[md.parent]
		for i,m in ipairs(pmd.vtable.entries) do
			md.vtable.entries:insert(m)
			md.methodimpl[m.field] = pmd.methodimpl[m.field]
			assert(md.methodimpl[m.field])
		end
		for i,v in ipairs(md.parent.entries) do
			if i > 1 then --skip the vtable
				self.entries:insert(i,v)
			end
		end
		parentinterfaces = pmd.interfaces
		for iface,_ in pairs(parentinterfaces) do
			md.interfaces[iface] = true
		end
	else
		parentinterfaces = {}
	end
	for methodname,impl in pairs(self.methods) do
		if terralib.isfunction(impl) and methodname ~= "alloc" and #impl:getdefinitions() == 1 then
			local impldef = impl:getdefinitions()[1]
			local success, typ = impldef:peektype()
			if not success then
				error("methods used in class system must have explicit return types")
			end
			if not md.methodimpl[methodname] then
				md.vtable.entries:insert { field = methodname, type = &typ }
			end
			md.methodimpl[methodname] = impldef
		end
	end
	for methodname,impl in pairs(md.methodimpl) do
		local _,typ = impl:peektype()
		local symbols = typ.parameters:map(symbol)
		local obj = symbols[1]
		local terra wrapper([symbols]) : typ.returns
			return obj.[vtablesym].[methodname]([symbols])
		end
		self.methods[methodname] = wrapper
	end
	local obj = symbol()
	local vtableinits = terralib.newlist()
	for iface,_ in pairs(md.interfaces) do
		local imd = interfacemetadata[iface]
		if not parentinterfaces[iface] then
			--we need an entry in the class for this interface object
			self.entries:insert { field = imd.name, type = iface }
		end
		--check the class implements the methods
		for methodname,_ in pairs(iface.methods) do
			if not md.methodimpl[methodname] then
				error("class does not implement method required by interface "..tostring(methodname))
			end
		end
		local vtableglobal = global(imd.vtable)
		md.interfaces[iface] = vtableglobal 
		vtableinits:insert(quote
			obj.[imd.name].[vtablesym] = &vtableglobal
		end)
	end
	md.vtableglobal = global(md.vtable)
	terra self.methods.init([obj] : &self)
		obj.[vtablesym] = &md.vtableglobal
		vtableinits
	end
    terra self:free()
        std.free(self)
    end
end
local function hasbeenfrozen(self)
	local md = metadata[self]
	local vtbl = md.vtableglobal:get()
	for methodname,impl in pairs(md.methodimpl) do
		impl:compile(function()
			vtbl[methodname] = impl:getpointer()  
		end)
	end
	for iface,ifacevtableglobal in pairs(md.interfaces) do
		local ifacevtable = ifacevtableglobal:get()
		local imd = interfacemetadata[iface]
		for methodname,_ in pairs(iface.methods) do
			local impl = md.methodimpl[methodname]
			impl:compile(function()
				ifacevtable[methodname] = terralib.cast(&uint8,impl:getpointer())
			end)
		end
		ifacevtable.__offset = terralib.offsetof(self,imd.name)
	end
end
local function issubclass(child,parent)
	if child == parent then
		return true
	else
		local md = metadata[child]
		return md and md.parent and issubclass(md.parent,parent)
	end
end
local function implementsinterface(child,parent)
	local md = metadata[child]
	return md and md.interfaces[parent]
end
local function castoperator(diag,tree,from,to,exp)
	if from:ispointer() and to:ispointer() then
		if issubclass(from.type,to.type) then
			return true, `to(exp)
		elseif implementsinterface(from.type,to.type) then
			local imd = interfacemetadata[to.type]
			return true, `&exp.[imd.name]
		end
	else
		return false
	end
end
local function initialize(c)
	if not metadata[c] then
		metadata[c] = { interfaces = {} }
		assert(not c.metamethods.__finalizelayout)
		assert(not c.metamethods.__hasbeenfrozen)
		assert(not c.metamethods.__cast)
		c.metamethods.__finalizelayout = finalizelayout
		c.metamethods.__hasbeenfrozen = hasbeenfrozen
		c.metamethods.__cast = castoperator
		terra c.methods.alloc()
        	var obj = [&c](std.malloc(sizeof(c)))
        	obj:init()
        	return obj
    	end
	end
end
function Class.extends(child,parent)
	assert(terralib.types.istype(child) and child:isstruct() and
	       terralib.types.istype(parent) and parent:isstruct())
	local md = metadata[child]
	if md and md.parent then
		error("already inherits from"..tostring(md.parent),2)
	end
	local cur = md
	while cur ~= nil do
		if cur.parent == child then
			error("recursively inheriting from itself",2)
		end
		cur = metadata[cur.parent]
	end
	initialize(parent)
	initialize(child)
	metadata[child].parent = parent
end
function Class.interface(ifacetable)
	local md = {}
	md.name = symbol()
	md.vtable = terralib.types.newstruct()
	local iface = terralib.types.newstruct("interface")
	iface.entries:insert { field = vtablesym, type = &md.vtable}
	md.vtable.entries:insert { field = "__offset", type = uint64 } --offset to get back to object
	for methodname,methodtype in pairs(ifacetable) do
		assert(type(methodname) == "string" and terralib.types.istype(methodtype) and methodtype:ispointertofunction())
		local params = terralib.newlist { &uint8 }
		for i,t in ipairs(methodtype.type.parameters) do 
			params:insert(t)
		end
		local fullmethodtype =  params -> methodtype.type.returns
		md.vtable.entries:insert { field = methodname, type = &uint8 }
		local args = methodtype.type.parameters:map(symbol)
		iface.methods[methodname] = terra(obj : &iface,[args]) : methodtype.type.returns
			var method = fullmethodtype(obj.[vtablesym].[methodname])
			var origobj = [&uint8](int64(obj) - obj.[vtablesym].__offset)
			return method(origobj,[args])
		end
	end
	interfacemetadata[iface] = md
	return iface
end
function Class.implements(child,iface)
	local imd = interfacemetadata[iface]
	assert(imd)
	local md = metadata[child]
	if not md then
		initialize(child)
		md = metadata[child]
	end
	md.interfaces[iface] = true
end
return Class