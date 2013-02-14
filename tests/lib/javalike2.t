local std = terralib.includec("stdlib.h")
local Class = {}

local metadata = {}
--map from class type to metadata about it:
-- parent = the type of the parent class or nil
-- methodimpl = methodname-funcdef table of the concrete implementations for this class
-- vtable = the type of the types vtable
-- vtableglobal = the global variable that holds the data for this vtable

local vtablesym = symbol()

local function abouttofreeze(self)
	local md = metadata[self]

	
	md.vtable = terralib.types.newstruct()
	md.methodimpl = {}

	self.entries:insert(1, { field = vtablesym, type = &md.vtable })
	if md.parent then
		md.parent:freeze(true) --asynchronous, only guarenteed to be in state "freezing" now
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
			local symbols = typ.parameters:map(symbol)
			local obj = symbols[1]
			local terra wrapper([symbols]) : typ.returns
				return obj.[vtablesym].[methodname]([symbols])
			end
			self.methods[methodname] = wrapper
		end
	end
	md.vtableglobal = global(md.vtable)
	terra self:init()
		self.[vtablesym] = &md.vtableglobal
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
end

local function issubclass(child,parent)
	if child == parent then
		return true
	else
		local md = metadata[child]
		return md and md.parent and issubclass(md.parent,parent)
	end
end

local function castoperator(diag,tree,from,to,exp)
	if from:ispointer() and to:ispointer() and issubclass(from.type,to.type) then
		return true, `to(exp)
	else
		return false
	end
end

local function initialize(c)
	if not metadata[c] then
		metadata[c] = {}
		assert(not c.metamethods.__abouttofreeze)
		assert(not c.metamethods.__hasbeenfrozen)
		assert(not c.metamethods.__cast)
		c.metamethods.__abouttofreeze = abouttofreeze
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


return Class