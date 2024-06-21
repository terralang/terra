local List = terralib.newlist
local C = terralib.includecstring [[
#include "stdio.h"
#include "stdlib.h"
]]
local malloc = C.malloc
local free = C.free
local printf = C.printf
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
local function Class(_,parent,...)
    local interfaces = {...}
    return function(T)
        print("metatype init of "..tostring(T))
        local mm = T.metamethods
        mm.parent = parent
        mm.methods = List()
        mm.methodtoidx = {}
        mm.interfaces = List()
        local ne
        if parent then
            ne = List{unpack(parent.entries)}
            mm.methods:insertall(parent.metamethods.methods)
            for k,v in pairs(parent.metamethods.methodtoidx) do
                print("importing",k,"at slot",v," in type ",tostring(T))
                mm.methodtoidx[k] = v
            end
            createvtable(T)
            for _, interface in ipairs(parent.metamethods.interfaces) do
                interface.implementors:insert(T)
                mm.interfaces:insert(interface)
            end
        else
            ne = List{ {field = "__vtable", type = &&opaque } }
        end
        ne:insertall(T.entries)
        for _,interface in ipairs(interfaces) do
            interface.implementors:insert(T)
            mm.interfaces:insert(interface)
            ne:insert { field = interface.label, type = interface.type } 
        end
        
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
        terra stubs.alloc()
            var r = [&T](malloc(sizeof(T)))
            stubs.init(r)
            return r
        end
        terra stubs.free(self : &T)
            free(self)
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

local function Interface(name,methodlist_)
    local iface = { implementors = List() }
    local struct Impl {}
    struct iface.type {
        __vtable : &Impl
    }
    function iface.type.metamethods:__typename() return name end
    iface.label = label(name)
    
    function iface.type.metamethods.__cast(from,to,exp)
        if to == &iface.type then
            for _,T in ipairs(iface.implementors) do
                if from == &T then
                    return `&exp.[iface.label]
                end
            end
            error("not a member of interface "..tostring(iface.type))
        end
        error("not a conversion to "..tostring(&iface.type))
    end
    function iface:Define(methodlist)
        methodlist = methodlist or methodlist_
        local methodtoidx = {}
        Impl.entries:insert { field = "__offset", type = int }
        for methodname,method in pairs(methodlist) do
            method = method.type
            local params = List{&opaque, unpack(method.parameters)}
            Impl.entries:insert { field = methodname, type = params -> method.returntype }
        end
        for methodname,method in pairs(methodlist) do
            method = method.type
            local syms = method.parameters:map(symbol)
            iface.type.methods[methodname] = terra(self : &iface.type,[syms]) : method.returntype
                printf("interface %s calling method %s\n",name,methodname)
                var obj = [&uint8](self) - self.__vtable.__offset
                return self.__vtable.[methodname](obj,[syms])
            end
        end
        for _,T in ipairs(iface.implementors) do
            print("defining interface "..tostring(name).." for type "..tostring(T))
            local ctor = List {} 
            for i,entry in ipairs(Impl.entries) do
                if i > 1 then
                    local methodname,method = entry.field,entry.type.type
                    local ttype = {&T, unpack(method.parameters,2)} -> method.returntype
                    local idx = T.metamethods.methodtoidx[methodname]
                    assert(idx,"method "..tostring(methodname).." not known in type "..tostring(T))
                    local method = T.metamethods.methods[idx]
                    --assert(ttype.type == method.type,("interface type %s and method type %s do not match"):format(tostring(ttype.type),tostring(method.type)))
                    ctor:insert(`[entry.type](method))
                end
            end
            local offset = assert(terralib.offsetof(T,iface.label),"no offset?")
            local vtable = constant(`Impl { offset, [ctor] })
            local terra oldinit :: &T -> &T
            oldinit:adddefinition(T.methods.init)
            T.methods.init:resetdefinition(terra(self : &T) : &T
                oldinit(self)
                self.[iface.label].__vtable = &vtable
                return self
            end)
        end
    end
    return iface
end

return setmetatable({ Interface = Interface, C = C }, { __call = Class })
