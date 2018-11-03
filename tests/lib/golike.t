
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
	self.vtabletype = terralib.types.newstruct("vtable")
	struct self.type {
		vtable: &self.vtabletype
		obj: &opaque
	}
	Interface.defined[self.type] = self
	self.type.metamethods.__cast = Interface.castmethod

	self.implementedtypes = {}

	self.methods = terralib.newlist()
	for k,v in pairs(methods) do
		print(k," = ",v)
		assert(v:ispointer() and v.type:isfunction())
		local params,rets = terralib.newlist{&opaque}, v.type.returntype
		local syms = terralib.newlist()
		for i,p in ipairs(v.type.parameters) do
			params:insert(p)
			syms:insert(symbol(p))
		end
		local typ = params -> rets
		self.methods:insert({name = k, type = typ, syms = syms})
		self.vtabletype.entries:insert { field = k, type = &opaque }
	end

	for _,m in ipairs(self.methods) do
		self.type.methods[m.name] = terra(interface : &self.type, [m.syms])
			var fn = m.type(interface.vtable.[m.name])
			return fn(interface.obj,[m.syms])
		end
	end

	return self.type
end

function Interface.interface:createcast(from,exp)
	if not self.implementedtypes[from] then
		local instance = {}
		local impl = terralib.newlist()
		for _,m in ipairs(self.methods) do
			local fn = from.methods[m.name]
			assert(fn and terralib.isfunction(fn))
			impl:insert(fn)
		end
		instance.vtable = constant(`[self.vtabletype] { [impl] })
		self.implementedtypes[from] = instance
	end

	local vtable = self.implementedtypes[from].vtable
	return `self.type { &vtable, [&opaque](exp) }
end

return Interface
