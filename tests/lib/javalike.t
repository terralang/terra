
IO = terralib.includec("stdio.h")
local std = terralib.includec("stdlib.h")
local Class = {}
Class.Class = {}
Class.Class.__index = Class.Class
Class.defined = {}

Class.Interface = {}
Class.Interface.__index = Class.Interface

Class.parentclasstable = {}
function Class.issubclass(c,t)
    if c == t then 
        return true 
    end
    local parent = Class.parentclasstable[c]
    if parent and Class.issubclass(parent,t) then
        return true
    end

    return false
end

local J = Class

function J.implementsiface(from,to)
    local builder = Class.defined[from]
    assert(builder)
    local ifacename = builder.interfacetypetoname[to]
    return ifacename ~= nil
end

function J.ifacename(from,to)
    local builder = Class.defined[from]
    assert(builder)
    local ifacename = builder.interfacetypetoname[to]
    return ifacename
end

function Class.castmethod(ctx,tree,from,to,exp)
  if from:ispointer() and to:ispointer() then
    if J.issubclass(from.type,to.type) then
      return true, `exp:as(to) --force cast
    elseif J.implementsiface(from.type,to.type) then
      --extract subobject with interface vtable:
      return true, `&exp.[J.ifacename(from.type,to.type)]
    else return false end --cast not valid
  end
end

function Class.Class:extends(parentclass)
    Class.parentclasstable[self.ttype] = parentclass
    self.parentbuilder = Class.defined[parentclass]
    self.parent = self.parentbuilder
    return self
end




function generatestubs(c,self)
        local initinterfaces = macro(function(ctx,tree,self)
            local stmts = terralib.newlist()
            for name,vtable in pairs(c.interfacevtables) do
                stmts:insert(quote
                    self.[name].__vtable = &vtable
                end)
            end
            return stmts
        end)

        local vtable = c.vtablevar
        
        terra self:init()
            self.__vtable = &vtable
            initinterfaces(self)
        end
        terra self.methods.alloc()
            var obj = std.malloc(sizeof(self)):as(&self)
            obj:init()
            return obj
        end
        terra self:free()
            std.free(self)
        end

end

function createvtable(c,self,ctx)
    c:createvtable(ctx)
    self:addentry("__vtable",&c.vtabletype)
end

function addinterfacevtable(c,self,interface)
    local function offsetinbytes(structtype,key)
        local terra offsetcalc() : int
            var a : &structtype = (0):as(&structtype)
            return (&a.[key]):as(&int8) - a:as(&int8)
        end
        return `offsetcalc()
    end
    local name = "__interface_"..interface.name
    if not c.interfacevtables[name] then
        self:addentry(name,interface:type())
        local methods = terralib.newlist()
        for _,m in ipairs(interface.methods) do
            local methodentry = Class.defined[self].vtablemap[m.name]
            assert(methodentry)
            assert(methodentry.name == m.name)
            --TODO: check that the types match...
            methods:insert(`methodentry.value:as(m.type))
        end
        local offsetofinterface = offsetinbytes(self,name)
        local var interfacevtable : interface.vtabletype = {offsetofinterface,methods}
        c.interfacevtables[name] = interfacevtable
        c.interfacetypetoname[interface:type()] = name
    end 
end

function createclass(factory)
  local newtype = terralib.types.newstruct()
  local function callback(self,ctx)
    local function layoutclass(cls)
      if cls.parent ~= nil then
        layoutclass(cls.parent)
      end
      for _,m in ipairs(cls.members) do
          newtype:addentry(m.name,m.type)
      end
      for _,iface in ipairs(cls.interfaces) do
        addinterfacevtable(factory,newtype,iface)
      end
    end
    createvtable(factory,newtype,ctx)
    layoutclass(factory)
    generatestubs(factory,newtype)
  end
  newtype:addlayoutfunction(callback)
  return newtype
end


function Class.class(parentclass)
    local c = setmetatable({},Class.Class)
    c.ttype = createclass(c)
    c.ttype.methods.__cast = Class.castmethod
    Class.defined[c.ttype] = c
    c.members = terralib.newlist()

    c.interfaces = terralib.newlist() --list of new interfaces added by this class, excluding parent's interfaces
    c.interfacetypetoname = {} --map from implemented interface types -> the name of the interface in the vtable

    c.interfacevtables = {}

    return c
end

function Class.Class:member(name,typ)
    self.members:insert( { name = name, type = typ })
    return self
end

function Class.Class:createvtableentries(ctx)
    if self.vtableentries ~= nil then
        return
    end

    self.vtableentries = terralib.newlist{}
    self.vtablemap = {}

    if self.parentbuilder then
        self.parentbuilder:createvtableentries(ctx)
        for _,i in ipairs(self.parentbuilder.vtableentries) do
            local e = {name = i.name, value = i.value}
            self.vtableentries:insert(e)
            self.vtablemap[i.name] = e
        end
    end
    for name,method in pairs(self.ttype.methods) do
        if terralib.isfunction(method) then
            if self.vtablemap[name] then
                --TODO: we should check that the types match...
                --but i am lazy
                self.vtablemap[name].value = method
            else
                local e = {name = name, value = method}
                self.vtableentries:insert(e)
                self.vtablemap[name] = e
            end
        end
    end

end

function Class.Class:createvtable(ctx)
    if not self.vtableentries then
        self:createvtableentries(ctx)
    end

    local vtabletype = terralib.types.newstruct("vtable")
    local inits = terralib.newlist()
    for _,e in ipairs(self.vtableentries) do
        assert(terralib.isfunction(e.value))
        assert(#e.value:getvariants() == 1)
        local variant = e.value:getvariants()[1]
        local success,typ = variant:peektype(ctx)
        assert(success)
        vtabletype:addentry(e.name,&typ)
        inits:insert(`e.value)
        local arguments = typ.parameters:map(symbol)
        local obj = arguments[1] 
        self.ttype.methods[e.name] = terra([arguments])
            return obj.__vtable.[e.name]([arguments])
        end
    end

    local var vtable : vtabletype = {inits}
    self.vtabletype = vtabletype
    self.vtablevar = vtable
end

function Class.Class:implements(interface)
    self.interfaces:insert(Class.defined[interface])
    return self
end

function Class.Class:type()
    return self.ttype
end

local interfaceid = 0
function Class.interface()
    local name = "interface_"..interfaceid
    interfaceid = interfaceid + 1
    local self = setmetatable({},Class.Interface)
    self.name = name
    self.methods = terralib.newlist()
    self.vtabletype = terralib.types.newstruct(name.."_vtable")
    self.vtabletype:addentry("offset",ptrdiff)
    self.interfacetype = terralib.types.newstruct(name)
    self.interfacetype:addentry("__vtable",&self.vtabletype)
    Class.defined[self.interfacetype] = self
    self.interfacetype.methods.__cast = Class.castmethod
    return self
end

function Class.Interface:method(name,typ)
    assert(typ:ispointer() and typ.type:isfunction())
    local returns = typ.type.returns
    local parameters = terralib.newlist({&uint8})
    local arguments = terralib.newlist()
    for _,e in ipairs(typ.type.parameters) do
        parameters:insert(e)
        arguments:insert(symbol(e))
    end
    local interfacetype = parameters -> returns
    self.methods:insert({name = name, type = interfacetype})
    self.vtabletype:addentry(name,interfacetype)
    
    local obj = symbol(&self.interfacetype)
    self.interfacetype.methods[name] = terra([obj],[arguments]) 
        return (obj.__vtable.[name])((obj):as(&uint8) - obj.__vtable.offset,[arguments]) 
    end
    return self
end

function Class.Interface:type()
    return self.interfacetype
end

return Class

