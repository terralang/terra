
local Class = {}

Class.class = {}
Class.class.__index = Class.class

Class.defined = {}

function Class.define(name,parentclass_)
    local c = setmetatable({},Class.class)
    
    c.ttype = terralib.types.newstruct(name)
    
    Class.defined[c.ttype] = c
    
    c.elements = terralib.newlist()
    
    if parentclass_ then
        local parentclass = Class.defined[parentclass_]
        assert(parentclass)
        setmetatable(c.ttype.methods, { __index = parentclass:type().methods })
        for i,e in ipairs(parentclass.elements) do
            c:member(e.name,e.type)
        end
        
        c.parent = parentclass
        
        function c.ttype.methods.__cast(ctx,tree,from,to,exp)
            if from:ispointer() and to:ispointer() then
                local fromS = from.type
                local toS = to.type
                if fromS == c.ttype then
                    local function isparent(cls)
                        if cls == nil then
                            return false
                        elseif cls.ttype == toS then
                            return true
                        else
                            return isparent(cls.parent)
                        end
                    end
                    
                    if isparent(c) then
                        return true, `exp:as(to)
                    end
                    
                end
            end
            return false 
        end
        
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

