local List = terralib.newlist

local function createvtable(T)
    return 
end
local function getcast(fromp,top,exp)
    if fromp:ispointer() and top:ispointer() then
        local from,to = fromp.type,top.type
        while from ~= to and from ~= nil do
            from = from.metamethods.parent
        end
        if from ~= nil then 
            return `[top](exp)
        end
    end
    error(tostring(fromp).." is not a subtype of "..tostring(top))
end
local function Class(parent)
    return function(T)
        print("metatype init of "..tostring(T))
        local mm = T.metamethods
        mm.parent = parent
        mm.methods = List()
        mm.methodtoidx = {}
        
        local ne
        if parent then
            ne = List{unpack(parent.entries)}
            mm.methods:insertall(parent.metamethods.methods)
            for k,v in pairs(parent.metamethods.methodtoidx) do
                print("importing",k,"at slot",v," in type ",tostring(T))
                mm.methodtoidx[k] = v
            end
            createvtable(T)
        else
            ne = List{ {field = "__vtable", type = &&opaque } }
        end
        ne:insertall(T.entries)
        T.entries = ne
        
        for name,m in pairs(T.methods) do
            local idx = mm.methodtoidx[name]
            if not idx then
                idx = #mm.methods + 1
                print("allocating slot "..tostring(idx).." to method "..name.." in type "..tostring(T))
            else print("override slot "..tostring(idx).." with method "..name.." in type "..tostring(T)) end
            mm.methods[idx] = m
            mm.methodtoidx[name] = idx
        end
        mm.vtableptr = terralib.constant(`arrayof([&opaque],[mm.methods]))
        
        local stubs = {}
        terra stubs.init(self : &T)
            self.__vtable = mm.vtableptr
            return self
        end
        for name,idx in pairs(mm.methodtoidx) do
            print("stub "..name.." in "..tostring(T))
            local m = mm.methods[idx]
            local typ = m:gettype()
            local params = typ.parameters:map(symbol)
            stubs[name] = terra([params]) : typ.returntype
                var fn = [&typ]([params[1]].__vtable[idx-1])
                return fn([params])
            end
        end
        T.methods = stubs
        T.metamethods.__cast = getcast
    end
end
return Class