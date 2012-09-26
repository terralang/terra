
local Class = {}
Class.class = {}
Class.class.__index = Class.class
Class.defined = {}

Class.parentclasstable = {}
function Class.issubclass(c,t)
    if c == t then return true end
    local parent = Class.parentclasstable[c]
    if not parent then return false
    else return Class.issubclass(parent,t) end
end

function Class.castmethod(ctx,tree,from,to,exp)
    if from:ispointer() and to:ispointer() and Class.issubclass(from.type,to.type) then
        return true, `exp:as(to)
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

    c.ttype:addlayoutfunction(function(self,ctx)
        local function addmembers(cls)
            local parent = Class.parentclasstable[cls]
            if parent then
                addmembers(parent)
            end
            local builder = Class.defined[cls]
            for i,m in ipairs(builder.members) do
                self:addentry(m.name,m.type)
            end
        end

        c:createvtable(ctx)
        self:addentry("__vtable",&c.vtabletype)
        addmembers(self)
        
    end)
    
    return c
end

function Class.class:member(name,typ)
    self.members:insert( { name = name, type = typ })
    return self
end

function Class.class:createvtable(ctx)
    if self.vtableentries ~= nil then
        return
    end

    print("CREATE VTABLE: ",self.name)
    self.vtableentries = terralib.newlist{}
    self.vtablemap = {}

    if self.parentbuilder then
        self.parentbuilder:createvtable(ctx)
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
    local vtabletype = terralib.types.newstruct(self.name.."_vtable")
    local inits = terralib.newlist()
    for _,e in ipairs(self.vtableentries) do
        assert(terralib.isfunction(e.value))
        assert(#e.value:getvariants() == 1)
        local variant = e.value:getvariants()[1]
        local success,typ = variant:peektype(ctx)
        assert(success)
        print(e.name,"->",&typ)
        vtabletype:addentry(e.name,&typ)
        inits:insert(`e.value)
        self.ttype.methods[e.name] = macro(function(ctx,tree,self,...)
            local arguments = {...}
            --this is wrong: it evaluates self twice, we need a new expression:  let x = <exp> in <exp> end 
            --to easily handle this case.
            --another way to do this would be to generate a stub function forward the arguments
            return `(terralib.select(self.__vtable,e.name))(&self,arguments)
        end)
    end

    local var vtable : vtabletype = {inits}
    self.vtabletype = vtabletype
    terra self.ttype:init()
        self.__vtable = &vtable
    end
end

function Class.class:implements(interface)
    error("implements - NYI")
end

function Class.class:type()
    return self.ttype
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

