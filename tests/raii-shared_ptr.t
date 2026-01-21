--load 'terralibext' to enable raii
require "terralibext"
local test = require("test")

local std = {}
std.io = terralib.includec("stdio.h")
std.lib = terralib.includec("stdlib.h")

local function printtestdescription(s)
    print()
    print("======================================")
    print(s)
    print("======================================")
end

--implementation of a smart (shared) pointer type
local function SharedPtr(T)

    local struct A{
        data : &T   --underlying data ptr (reference counter is stored in its head)
    }

    --table for static methods
    local static_methods = {}

    A.metamethods.__getmethod = function(self, methodname)
        return A.methods[methodname] or static_methods[methodname] or error("No method " .. methodname .. "defined on " .. self)
    end

    A.methods.refcounter = terra(self : &A)
        if self.data ~= nil then
            return ([&int8](self.data))-1
        end
        return nil
    end

    A.methods.increaserefcounter = terra(self : &A)
        var ptr = self:refcounter()
        if  ptr ~= nil then
            @ptr = @ptr+1
        end
    end

    A.methods.decreaserefcounter = terra(self : &A)
        var ptr = self:refcounter()
        if  ptr ~= nil then
            @ptr = @ptr-1
        end
    end

    A.methods.__dereference = terra(self : &A)
        return @self.data
    end

    static_methods.new = terra()
        std.io.printf("new: allocating memory. start\n")
        defer std.io.printf("new: allocating memory. return.\n")
        --heap allocation for `data` with the reference counter `refcount` stored in its head and the real data in its tail
        var head = sizeof(int8)
        var tail = sizeof(T)
        var ptr = [&int8](std.lib.malloc(head+tail))
        --assign to data
        var x = A{[&T](ptr+1)}
        --initializing the reference counter to one
        @x:refcounter() = 1
        return x
    end

    A.methods.__init = terra(self : &A)
        std.io.printf("__init: initializing object\n")
        self.data = nil       -- initialize data pointer to nil
        std.io.printf("__init: initializing object. return.\n")
    end

    A.methods.__dtor = terra(self : &A)
        std.io.printf("__dtor: calling destructor. start\n")
        defer std.io.printf("__dtor: calling destructor. return\n")
        --if uninitialized then do nothing
        if self.data == nil then
            return
        end
        --the reference counter is `nil`, `1` or `> 1`.
        if @self:refcounter() == 1 then
            --free memory if the last shared pointer obj runs out of life
            std.io.printf("__dtor: reference counter: %d -> %d.\n", @self:refcounter(), @self:refcounter()-1)
            std.io.printf("__dtor: free'ing memory.\n")
            std.lib.free(self:refcounter())
            self.data = nil --reinitialize data ptr
        else
            --otherwise reduce reference counter
            self:decreaserefcounter()
            std.io.printf("__dtor: reference counter: %d -> %d.\n", @self:refcounter()+1, @self:refcounter())
        end
    end

    A.methods.__copy = terra(from : &A, to : &A)
        std.io.printf("__copy: calling copy-assignment operator. start\n")
        defer std.io.printf("__copy: calling copy-assignment operator. return\n")
        to.data = from.data
        to:increaserefcounter()
    end

    --return parameterized shared pointer type
    return A
end

local shared_ptr_int = SharedPtr(int)

printtestdescription("shared_ptr - copy construction.")
local terra test0()
    var a : shared_ptr_int
    std.io.printf("main: a.refcount: %p\n", a:refcounter())
    a = shared_ptr_int.new()
    @a.data = 10
    std.io.printf("main: a.data: %d\n", @a.data)
    std.io.printf("main: a.refcount: %d\n", @a:refcounter())
    var b = a
    std.io.printf("main: b.data: %d\n", @b.data)
    std.io.printf("main: a.refcount: %d\n", @a:refcounter())
    if a:refcounter()==b:refcounter() then
        return @b.data * @a:refcounter()  --10 * 2
    end
end
test.eq(test0(), 20)

printtestdescription("shared_ptr - copy assignment.")
local terra test1()
    var a : shared_ptr_int, b : shared_ptr_int
    std.io.printf("main: a.refcount: %p\n", a:refcounter())
    a = shared_ptr_int.new()
    @a.data = 11
    std.io.printf("main: a.data: %d\n", @a.data)
    std.io.printf("main: a.refcount: %d\n", @a:refcounter())
    b = a
    std.io.printf("main: b.data: %d\n", @b.data)
    std.io.printf("main: a.refcount: %d\n", @a:refcounter())
    if a:refcounter()==b:refcounter() then
        return @b.data * @a:refcounter()  --11 * 2
    end
end
test.eq(test1(), 22)

