local std = terralib.includec("stdlib.h")
local Class = {}
local metadata = {}
--map from class type to metadata about it:
-- parent = the type of the parent class or nil
-- methodimpl = methodname-funcdef table of the concrete implementations for this class
-- vtable = the type of the types vtable
-- vtableglobal = the global variable that holds the data for this vtable

local function getdefinitionandtype(impl)
	local impldef = impl:getdefinitions()[1]
	local success, typ = impldef:peektype()
	if not success then
		error("methods used in class system must have explicit return types")
	end
	return impldef,typ
end

local function issubclass(child,parent)
	if child == parent then
		return true
	else
		local md = metadata[child]
		return md and md.parent and issubclass(md.parent,parent)
	end
end

local function createstub(methodname,typ)
	local symbols = typ.parameters:map(symbol)
	local obj = symbols[1]
	local terra wrapper([symbols]) : typ.returns
		return obj.__vtable.[methodname]([symbols])
	end
	return wrapper
end

local function hasbeenfrozen(self)
	local md = metadata[self]
	local vtbl = md.vtable:get()
	for methodname,impl in pairs(md.methodimpl) do
		impl:compile(function()
			vtbl[methodname] = impl:getpointer()  
		end)
	end
end

local function copyparentlayout(self,parent)
	local md = metadata[self]
	local pmd = metadata[parent]
	for i,m in ipairs(pmd.vtabletype.entries) do
		md.vtabletype.entries:insert(m)
		md.methodimpl[m.field] = pmd.methodimpl[m.field]
	end
	for i = 2,#parent.entries do 
		self.entries:insert(i,parent.entries[i])
	end
end

local function initializevtable(self)
	local md = metadata[self]
	md.vtable = global(md.vtabletype)
	terra self:init()
		self.__vtable = &md.vtable
	end
end
local function finalizelayout(self)
	local md = metadata[self]
	struct md.vtabletype {}
	md.methodimpl = {}
	self.entries:insert(1, { field = "__vtable", type = &md.vtabletype })
	if md.parent then
		md.parent:finalizelayout()
		copyparentlayout(self,md.parent)
	end
	for methodname,impl in pairs(self.methods) do
		local impldef,typ = getdefinitionandtype(impl)			
		if md.methodimpl[methodname] == nil then
			md.vtabletype.entries:insert { field = methodname, type = &typ }
		end
		md.methodimpl[methodname] = impldef
	end
	for methodname,impl in pairs(md.methodimpl) do
		local _,typ = impl:peektype()
		self.methods[methodname] = createstub(methodname,typ)
	end
	initializevtable(self)
end

local function castoperator(diag,tree,from,to,exp)
	if from:ispointer() and to:ispointer() and issubclass(from.type,to.type) then
		return true,`[to](exp)
	end
	error("not a subtype")
end

local function registermetamethods(c)
	if not metadata[c] then
		metadata[c] = {}
		c.metamethods.__finalizelayout = finalizelayout
		c.metamethods.__hasbeenfrozen = hasbeenfrozen
		c.metamethods.__cast = castoperator
	end
end

function Class.extends(child,parent)
	registermetamethods(parent) 
	registermetamethods(child)
	metadata[child].parent = parent
end

return Class