
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
    
    c.elements = terralib.newlist()
    
    if parentclass then
        local parentclassbuilder = Class.defined[parentclass]
        assert(parentclassbuilder)
        setmetatable(c.ttype.methods, { __index = parentclass.methods })    
        for i,e in ipairs(parentclassbuilder.elements) do
            c:member(e.name,e.type)
        end
        Class.parentclasstable[c.ttype] = parentclass
    end
    
    return c
end

function Class.class:member(name,typ)
    self.elements:insert( { name = name, type = typ })
    self.ttype:addentry(name,typ)
    return self
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
    
terra A:double()
    return self.a*2
end
    
B = Class.define("B",A)
    :member("b",int)
    :type()
    
terra B:combine()
    return self.b + self.a
end
    
C = Class.define("C",B)
    :member("c",double)
    :type()
    
C.methods.combine = terra(self : &C)
    return self.c + self.a + self.b
end


terra foobar()
    var a = A { 1 }
    var b = B { 1, 2 }
    var c = C { 1, 2, .25 }
    
    return a:double() + b:double() + c:double() + b:combine() + c:combine()
end
local test = require("test")
test.eq(12.25,foobar())

