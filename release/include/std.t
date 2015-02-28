local S = {}

S.memoize = terralib.memoize

--TODO: for speed we should just declare the methods we need directly using
-- terra, but we need an API to do this
local C = terralib.includecstring [[
#include <stdio.h>
#include <stdlib.h>
]]

S.rundestructor = macro(function(self)
    local T = self:gettype()
    local function hasdtor(T) --avoid generating code for empty array destructors
        if T:isstruct() then return T:getmethod("destruct") 
        elseif T:isarray() then return hasdtor(T.type) 
        else return false end
    end
    if T:isstruct() then
        local d = T:getmethod("destruct")
        if d then
            return `self:destruct()
        end
    elseif T:isarray() and hasdtor(T) then        
        return quote
            var pa = &self
            for i = 0,T.N do
                S.rundestructor((@pa)[i])
            end
        end
    end
    return quote end
end)

S.assert = macro(function(check)
    local loc = check.tree.filename..":"..check.tree.linenumber
    return quote 
        if not check then
            C.printf("%s: assertion failed!\n",loc)
            C.abort()
        end
    end
end) 

local generatedtor = macro(function(self)
    local T = self:gettype()
    local stmts = terralib.newlist()
    if T.methods.__destruct then
        stmts:insert(`self:__destruct())
    end
    local entries = T:getentries()
    for i,e in ipairs(entries) do
        if e.field then --not a union
            stmts:insert(`S.rundestructor(self.[e.field]))
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
        generatedtor(@self)
    end
end


function S.Vector(T,debug)
    local struct Vector(S.Object) {
        _data : &T;
        _size : uint64;
        _capacity : uint64;
    }
    function Vector.metamethods.__typename() return ("Vector(%s)"):format(tostring(T)) end
    local assert = debug and S.assert or macro(function() return quote end end)
    terra Vector:init() : &Vector
        self._data,self._size,self._capacity = nil,0,0
        return self
    end
    terra Vector:init(cap : uint64) : &Vector
        self:init()
        self:reserve(cap)
        return self
    end
    terra Vector:reserve(cap : uint64)
        if cap > 0 and cap > self._capacity then
            var oc = self._capacity
            if self._capacity == 0 then
                self._capacity = 16
            end
            while self._capacity < cap do
                self._capacity = self._capacity * 2
            end
            self._data = [&T](S.realloc(self._data,sizeof(T)*self._capacity))
        end
    end
    terra Vector:__destruct()
        assert(self._capacity >= self._size)
        for i = 0ULL,self._size do
            S.rundestructor(self._data[i])
        end
        if self._data ~= nil then
            C.free(self._data)
            self._data = nil
        end
    end
    terra Vector:size() return self._size end
    
    terra Vector:get(i : uint64)
        assert(i < self._size) 
        return &self._data[i]
    end
    Vector.metamethods.__apply = macro(function(self,idx)
        return `@self:get(idx)
    end)
    
    terra Vector:insert(idx : uint64, N : uint64, v : T) : {}
        assert(idx <= self._size)
        self._size = self._size + N
        self:reserve(self._size)

        if self._size > N then
            var i = self._size
            while i > idx do
                self._data[i - 1] = self._data[i - 1 - N]
                i = i - 1
            end
        end

        for i = 0ULL,N do
            self._data[idx + i] = v
        end
    end
    terra Vector:insert(idx : uint64, v : T) : {}
        return self:insert(idx,1,v)
    end
    terra Vector:insert(v : T) : {}
        return self:insert(self._size,1,v)
    end
    terra Vector:insert() : &T
        self._size = self._size + 1
        self:reserve(self._size)
        return self:get(self._size - 1)
    end
    terra Vector:remove(idx : uint64) : T
        assert(idx < self._size)
        var v = self._data[idx]
        self._size = self._size - 1
        for i = idx,self._size do
            self._data[i] = self._data[i + 1]
        end
        return v
    end
    terra Vector:remove() : T
        assert(self._size > 0)
        return self:remove(self._size - 1)
    end
    
    return Vector
end

S.Vector = S.memoize(S.Vector)

--import common C functions into std object table
for k,v in pairs(C) do
    S[k] = v
end

return S