local S = {}

S.memoize = terralib.memoizefunction

--TODO: for speed we should just declare the methods we need directly using
-- terra, but we need an API to do this
local C = terralib.includecstring [[
#include <stdio.h>
#include <stdlib.h>
]]

local generatedtor = macro(function(T,self)
    T = T:astype()
    local stmts = terralib.newlist()
    if T.methods.__destruct then
        stmts:insert(`self:__destruct())
    end
    local entries = T:getentries()
    local function hasdtor(T) --avoid generating code for empty array destructors
        if T:isstruct() then return T:getmethod("destruct") 
        elseif T:isarray() then return hasdtor(T.type) 
        else return false end
    end
    local function add(T,exp)
        if T:isstruct() then
            local d = T:getmethod("destruct")
            if d then
                return `exp:destruct()
            end
        elseif T:isarray() and hasdtor(T) then        
            return quote
                for i = 0,T.N do
                    [add(T.type,`exp[i])]
                end
            end
        end
        return quote end
    end
    for i,e in ipairs(entries) do
        if e.field then --not a union
            stmts:insert(add(e.type,`self.[e.field]))
        end
    end
    return stmts
end)

-- standard object metatype
-- provides T.alloc(), T.salloc(), obj:destruct(), obj:delete()
-- users should define __destruct if the object has custom destruct behavior
-- destruct will call destruct on child nodes
function S.Object(T)
    --fill in special methods/macros
    terra T:delete()
        self:destruct()
        C.free(self)
    end 
    terra T.methods.alloc()
        return [&T](C.malloc(sizeof(T)))
    end
    T.methods.salloc = macro(function()
        return quote 
            var t : T
            defer t:destruct()
        in
            &t
        end
    end)
    terra T:destruct()
        generatedtor(T,self)
    end
end

for k,v in pairs(C) do
    S[k] = v
end

return S