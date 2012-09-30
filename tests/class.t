
IO = terralib.includec("stdio.h")
local Class = {}
Class.class = {}
Class.class.__index = Class.class
Class.defined = {}

Class.interface = {}
Class.interface.__index = Class.interface

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

function Class.castmethod(ctx,tree,from,to,exp)
    if from:ispointer() and to:ispointer() then
        if Class.issubclass(from.type,to.type) then
            return true, `exp:as(to)
        end
        local builder = Class.defined[from.type]
        assert(builder)
        local ifacename = builder.interfacetypetoname[to.type]
        if ifacename then
            return true, `&exp.[ifacename]
        end
    end
    return false
end

function Class.define(name,parentclass)
    local c = setmetatable({},Class.class)
    c.ttype = terralib.types.newstruct(name)
    c.ttype.methods.__cast = Class.castmethod
    Class.defined[c.ttype] = c
    c.members = terralib.newlist()
    Class.parentclasstable[c.ttype] = parentclass
    c.parentbuilder = Class.defined[parentclass]
    c.name = name
    
    c.interfaces = terralib.newlist() --list of new interfaces added by this class, excluding parent's interfaces
    c.interfacetypetoname = {} --map from implemented interface types -> the name of the interface in the vtable

    c.ttype:addlayoutfunction(function(self,ctx)

        local interfacevtables = {}
        local function addinterface(interface)
            local function offsetinbytes(structtype,key)
                local terra offsetcalc() : int
                    var a : &structtype = (0):as(&structtype)
                    return (&a.[key]):as(&int8) - a:as(&int8)
                end
                return `offsetcalc()
            end
            local name = "__interface_"..interface.name
            if not interfacevtables[name] then
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
                interfacevtables[name] = interfacevtable
                c.interfacetypetoname[interface:type()] = name
            end
        end

        local function addmembers(cls)
            local parent = Class.parentclasstable[cls]
            if parent then
                addmembers(parent)
            end
            local builder = Class.defined[cls]
            for i,m in ipairs(builder.members) do
                self:addentry(m.name,m.type)
            end
            for i,interface in ipairs(builder.interfaces) do
                addinterface(interface)
            end
        end

        c:createvtable(ctx)

        self:addentry("__vtable",&c.vtabletype)
        addmembers(self)

        local initinterfaces = macro(function(ctx,tree,self)
            local stmts = terralib.newlist()
            for name,vtable in pairs(interfacevtables) do
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

    end)
    
    return c
end

function Class.class:member(name,typ)
    self.members:insert( { name = name, type = typ })
    return self
end

function Class.class:createvtableentries(ctx)
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

function Class.class:createvtable(ctx)
    if not self.vtableentries then
        self:createvtableentries(ctx)
    end

    local vtabletype = terralib.types.newstruct(self.name.."_vtable")
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
        local stub
        if #typ.returns > 0 then --TODO: should we allow return and other multistatements to result in 0 values?
                                 --TODO: you should be able to write arguments in expression, but 
                                 -- the way luaexpression and quotations are handled doesn't work that way
                                 -- we need to add a generic "list of specials" expression that 
                                 -- replaces luaexpression and quote in checkparameter list
                                 -- this will also fix some bugs with how checkspecial works with lists
            stub = terra([arguments])
                return obj.__vtable.[e.name]([arguments])
            end
        else
            stub = terra([arguments])
               obj.__vtable.[e.name]([arguments])
            end
        end
        self.ttype.methods[e.name] = stub 
    end

    local var vtable : vtabletype = {inits}
    self.vtabletype = vtabletype
    self.vtablevar = vtable
end

function Class.class:implements(interface)
    self.interfaces:insert(Class.defined[interface])
    return self
end

function Class.class:type()
    return self.ttype
end

function Class.defineinterface(name)
    local self = setmetatable({},Class.interface)
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

function Class.interface:method(name,typ)
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
    local call = `(obj.__vtable.[name])((obj):as(&uint8) - obj.__vtable.offset,[arguments])
    if #returns > 0 then
        stub = terra([obj],[arguments]) return call end
    else
        stub = terra([obj],[arguments]) call end
    end
    self.interfacetype.methods[name] = stub

    return self
end

function Class.interface:type()
    return self.interfacetype
end

A = Class.define("A")
    :member("a",int)
    :type()
    
terra A:double() : int
    return self.a*2
end
    
B = Class.define("B",A)
    :member("b",int)
    :type()
    
terra B:combine(a : int) : int
    return self.b + self.a + a
end
    
C = Class.define("C",B)
    :member("c",double)
    :type()
    
terra C:combine(a : int) : int
    return self.c + self.a + self.b + a
end

terra C:double() : double
    return self.a * 4
end

terra doubleAnA(a : &A)
    return a:double()
end

terra combineAB(b : &B)
    return b:combine(3)
end

terra returnA(a : A)
    return a
end

terra foobar()

    var a = A {nil, 1 }
    var b = B {nil, 1, 2 }
    var c = C {nil, 1, 2, 3.5 }
    a:init()
    b:init()
    c:init()
    return doubleAnA(&a) + doubleAnA(&b) + doubleAnA(&c) + combineAB(&b) + combineAB(&c)
end
local test = require("test")
test.eq(23,foobar())


local Doubles
= Class.defineinterface("Doubles")
  :method("double",{} -> int)
  :type()

local Adds
= Class.defineinterface("Adds")
  :method("add", int -> int)
  :type()

local D 
= Class.define("D")
  :member("data",int)
  :implements(Doubles)
  :implements(Adds)
  :type()

terra D:double() : int
    return self.data * 2
end

terra D:add(a : int) : int
    return self.data + a
end


terra aDoubles(a : &Doubles)
    return a:double()
end

terra aAdds(a : &Adds)
    return a:add(3)
end

terra foobar2()
    var a : D
    a:init()
    a.data = 3
    return aDoubles(&a) + aAdds(&a)
end

test.eq(12,foobar2())

Animal = Class.define("Animal")
         :member("data",int)
         :type()
terra Animal:speak() : {}
    IO.printf("... %d\n",self.data)
end

Dog = Class.define("Dog",Animal)
      :type()
terra Dog:speak() : {}
    IO.printf("woof! %d\n",self.data)
end

Cat = Class.define("Cat",Animal)
      :type()
terra Cat:speak() : {}
    IO.printf("meow! %d\n",self.data)
end

terra dospeak(a : &Animal)
    a:speak()
end

terra barnyard()
    var c : Cat
    var d : Dog
    c:init()
    d:init()
    c.data,d.data = 0,1

    dospeak(&c)
    dospeak(&d)
end

barnyard()

local Add = Class.defineinterface("Add")
            :method("add",int->int)
            :type()

local Sub = Class.defineinterface("Sub")
            :method("sub",int->int)
            :type()

local P = Class.define("P")
          :member("data",int)
          :implements(Add)
          :type()

local C = Class.define("C",P)
          :member("data2",int)
          :implements(Sub)
          :type()

terra P:add(b : int) : int
    return self.data + b
end

terra C:sub(b : int) : int
    return self.data2 - b
end

terra doadd(a : &Add)
    return a:add(1)
end

terra dopstuff(p : &P)
    return p:add(2) + doadd(p) 
end

terra dosubstuff(s : &Sub)
    return s:sub(1)
end

terra dotests()
    var p : P
    p:init()
    var c : C
    c:init()
    p.data = 1
    c.data = 1
    c.data2 = 2
    return dopstuff(&p) + dopstuff(&c) + dosubstuff(&c)
end

test.eq(dotests(),11)





