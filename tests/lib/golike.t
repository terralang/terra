
local Interface = {}

Interface.interface = {}
Interface.interface.__index = Interface.interface
Interface.defined = {}

function Interface.castmethod(from,to,exp)
	if to:isstruct() and from:ispointertostruct() then
		local self = Interface.defined[to]
		if not self then error("not a interface") end
		local cst = self:createcast(from.type,exp)
		return cst
	end
	error("invalid cast")
end
function Interface.create(methods)
	local self = setmetatable({},Interface.interface)
	struct self.type {
		data : uint64
	}
	Interface.defined[self.type] = self
	self.type.metamethods.__cast = Interface.castmethod

	self.nextid = 0
	self.allocatedsize = 256
	self.implementedtypes = {} 
	
	self.methods = terralib.newlist()
	self.vtabletype = terralib.types.newstruct("vtable")
	for k,v in pairs(methods) do
		print(k," = ",v)
		assert(v:ispointer() and v.type:isfunction())
		local params,rets = terralib.newlist{&uint8}, v.type.returntype
		local syms = terralib.newlist()
		for i,p in ipairs(v.type.parameters) do
			params:insert(p)
			syms:insert(symbol(p))
		end
		local typ = params -> rets
		self.methods:insert({name = k, type = typ, syms = syms})
		self.vtabletype.entries:insert { field = k, type = &uint8 }
	end
	self.vtables = global(&self.vtabletype)
	self.vtablearray = terralib.new(self.vtabletype[self.allocatedsize])
	self.vtables:set(self.vtablearray)

	for _,m in ipairs(self.methods) do
		self.type.methods[m.name] = terra(interface : &self.type, [m.syms])
			var id = interface.data >> 48
			var mask = (1ULL << 48) - 1
			var obj = [&uint8](mask and interface.data)
			return  m.type(self.vtables[id].[m.name])(obj,[m.syms])
		end
	end

	return self.type
end

function Interface.interface:createcast(from,exp)
	if not self.implementedtypes[from] then
		local instance = {}
		instance.id = self.nextid
		assert(instance.id < self.allocatedsize) --TODO: handle resize
		local vtableentry = self.vtablearray[self.nextid]
		self.nextid = self.nextid + 1
		for _,m in ipairs(self.methods) do
			local fn = from.methods[m.name]
			assert(fn and terralib.isfunction(fn))
			vtableentry[m.name] = terralib.cast(&uint8,fn:getpointer()) 
		end
		self.implementedtypes[from] = instance
	end

	local id = self.implementedtypes[from].id
	return `self.type { uint64(exp) or (uint64(id) << 48) }
end

return Interface