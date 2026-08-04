require "terralibext"
local C = terralib.includecstring[[
	#include <stdlib.h>
    #include <string.h>
]]
local utils = require("lib.utils")

--Implementation of a Dynamic Stack class that stores its data on the heap.
--the following RAII methods are implemented/generated
--__dtor (user implemented)
--__init (user implemented)
--__move (auto-generated)
--__copy (conditionally compiled and user implemented)
local DynamicStack = terralib.memoize(function(T, copyable)

    local struct Stack {
        data : &T       -- Pointer to heap-allocated elements
        size : int      -- Current number of elements
        capacity : int  -- Maximum capacity before reallocation
    }

    -- This table stores all the static methods
    Stack.staticmethods = {}

    -- Enable static method dispatch (e.g., Stack.new)
    Stack.metamethods.__getmethod = function(self, methodname)
        return self.methods[methodname] or Stack.staticmethods[methodname]
    end

    terra Stack:size() return self.size end
    terra Stack:capacity() return self.capacity end

    -- Macro for get/set access: stack(i)
    Stack.metamethods.__apply = macro(function(self, i)
        return `self.data[i]
    end)

    -- Initialize with null pointer and zero size/capacity
    terra Stack:__init()
        self.data = nil
        self.size = 0
        self.capacity = 0
    end

    -- Free heap memory and reset state
    terra Stack:__dtor()
        if self.data~=nil then
            utils.printf("Deleting DynamicStack.\n")
            C.free(self.data)
            self.data = nil
        end
    end

    --conditional compilation, adding a __copy method to provide value-semantics
    if copyable then
        --deepcopy of Stack data structure
        terra Stack.methods.__copy(from : &Stack, to : &Stack)
            utils.printf("Copying DynamicStack.\n")
            to:__dtor() --delete old memory, just in case
            to.data = [&T](C.malloc(from.capacity * sizeof(T))) --allocate new memory
            C.memcpy(to.data, from.data, from.size * sizeof(T)) --copy data over
            to.size, to.capacity =  from.size, from.capacity --set new size and capacity
        end
    end

    -- Create a new stack with initial capacity
    Stack.staticmethods.new = terra(capacity : int)
        return Stack{data=[&T](C.malloc(capacity * sizeof(T))), capacity=capacity}
    end

    -- Reallocate when capacity is exceeded
    terra Stack:realloc(capacity : int)
        utils.printf("Reallocating DynamicStack.\n")
        self.data = [&T](C.realloc(self.data, capacity * sizeof(T)))
        self.capacity = capacity
    end

    -- Push an element, moving it into the stack
    terra Stack:push(v : T)
        if self.size == self.capacity then
            self:realloc(1 + 2 * self.capacity) -- Double capacity plus one
        end
        self.size = self.size + 1
        self.data[self.size - 1] = __move__(v) -- Explicit move, avoiding copy when `v` is managed and copyable
    end

    -- Pop an element, moving it out
    terra Stack:pop()
        if self.size > 0 then
            var tmp = __move__(self.data[self.size - 1]) -- Explicit move, cleaning resources of Stack element in case `T` is managed
            self.size = self.size - 1
            return tmp
        end
    end

    return Stack
end)


--Implementation of a Dynamic Vector class that stores its data on the heap.
--the following RAII methods are implemented/generated
--__dtor (user implemented)
--__init (user implemented)
--__move (auto-generated)
--__copy (conditionally compiled and user implemented)
local DynamicVector = terralib.memoize(function(T, copyable)

    local struct Vector {
        data : &T   -- Pointer to fixed heap memory
        size : int  -- Number of elements
    }

    -- This table stores all the static methods
    Vector.staticmethods = {}

    -- Enable static method dispatch (e.g., Vector.new)
    Vector.metamethods.__getmethod = function(self, methodname)
        return self.methods[methodname] or Vector.staticmethods[methodname]
    end

    -- Initialize with null pointer and zero size
    terra Vector:__init()
        self.data = nil
        self.size = 0
    end

    -- Free heap memory and reset
    terra Vector:__dtor()
        if self.data~=nil then
            utils.printf("Deleting DynamicVector.\n")
            C.free(self.data)
            self.data = nil
            self.size = 0
        end
    end

    -- vector_copy_start
    --conditional compilation, adding a __copy method to provide value-semantics
    if copyable then
        --deepcopy of Vector data structure
        terra Vector.methods.__copy(from : &Vector, to : &Vector)
            utils.printf("Copying DynamicVector.\n")
            to:__dtor() --delete old memory, just in case
            to.data = [&T](C.malloc(from.size * sizeof(T))) --allocate new memory
            C.memcpy(to.data, from.data, from.size * sizeof(T)) --copy data over
            to.size =  from.size --set new size
        end
    end
    -- vector_copy_end

    terra Vector:size() return self.size end

    -- Macro for get/set access: vector(i)
    Vector.metamethods.__apply = macro(function(self, i)
        return `self.data[i]
    end)

    -- Allocate a dynamic vector of `size`
    Vector.staticmethods.new = terra(size : int)
        return Vector{data=[&T](C.malloc(size * sizeof(T))), size=size}
    end

    -- Import DynamicStack for casting
    local Stack = DynamicStack(T, copyable)

    -- Reinterprete a reference to a stack to a reference of a vector. This is for example used in `__move :: {&Vector, &Vector}` when one of the arguments is a pointer to a stack
    Vector.metamethods.__cast = function(from, to, exp)
        if from:ispointer() and from.type == Stack and to:ispointer() and to.type == Vector then
            return quote
                exp.capacity = 0 -- Invalidate Stack’s ownership
            in
                [&Vector](exp) -- Transfer to &Vector, preps for `__move :: {&Vector, &Vector} -> {}`
            end
        else
            error("ArgumentError: not able to cast " .. tostring(from) .. " to " .. tostring(to) .. ".")
        end
    end

    return Vector
end)

--Implementation of a VectorPair class that stores two vectors on the heap
--the following RAII methods are implemented/generated
--__dtor (auto-generated)
--__init (auto-generated
--__move (auto-generated)
--__copy (conditionally autogenerated when copyable=true)
local VectorPair = terralib.memoize(function(T, copyable)

    local Vector = DynamicVector(T, copyable)

    local struct Pair {
        first : Vector
        second : Vector
    }

    -- This table stores all the static methods
    Pair.staticmethods = {}

    -- Enable static method dispatch (e.g., Pair.new)
    Pair.metamethods.__getmethod = function(self, methodname)
        return self.methods[methodname] or Pair.staticmethods[methodname]
    end

    -- Create a new `VectorPair`. Note that the function arguments are passed by value. 
    -- If `Vector` implement `__copy`, the function argumens will be copied. Otherwise
    -- the resource will be moved by default.
    Pair.staticmethods.new = terra(first : Vector, second : Vector)
        utils.assert(first:size() == second:size(), "Error: sizes are not compatible.")
        return Pair{first=__move__(first), second=__move__(second)}
    end

    -- Macro for get/set access: dualvector(i)
    Pair.metamethods.__apply = macro(function(self, i)
        return quote
        in
            self.first(i), self.second(i)
        end
    end)

    terra Pair:size() return self.first:size() end

    return Pair
end)

return {
    DynamicStack = DynamicStack,
    DynamicVector = DynamicVector,
    VectorPair = VectorPair
}