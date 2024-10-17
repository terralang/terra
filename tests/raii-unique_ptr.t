require "terralibext"  --load 'terralibext' to enable raii

local std = {
    io = terralib.includec("stdio.h"),
    lib = terralib.includec("stdlib.h")
}

local function printtestheader(s)
    print()
    print("===========================")
    print(s)
    print("===========================")
end

struct A{
    data : &int
    heap : bool
}

A.methods.__init = terra(self : &A)
    std.io.printf("__init: initializing object. start.\n")
    self.data = nil         -- initialize data pointer to nil
    self.heap = false       --flag to denote heap resource
    std.io.printf("__init: initializing object. return.\n")
end

A.methods.__dtor = terra(self : &A)
    std.io.printf("__dtor: calling destructor. start\n")
    defer std.io.printf("__dtor: calling destructor. return\n")
    if self.heap then
        std.lib.free(self.data)
        self.data = nil
        self.heap = false
        std.io.printf("__dtor: freed memory.\n")
    end
end

A.methods.__copy = terralib.overloadedfunction("__copy")
A.methods.__copy:adddefinition(
terra(from : &A, to : &A)
    std.io.printf("__copy: moving resources {&A, &A} -> {}.\n")
    to.data = from.data
    to.heap = from.heap
    from.data = nil
    from.heap = false
end)
A.methods.__copy:adddefinition(
terra(from : &int, to : &A)
    std.io.printf("__copy: assignment {&int, &A} -> {}.\n")
    to.data = from
    to.heap = false --not known at compile time
end)

--dereference ptr
terra A.methods.getvalue(self : &A)
    return @self.data
end

terra A.methods.setvalue(self : &A, value : int)
    @self.data = value
end

--heap memory allocation
terra A.methods.allocate(self : &A)
    std.io.printf("allocate: allocating memory. start\n")
    defer std.io.printf("allocate: allocating memory. return.\n")
    self.data = [&int](std.lib.malloc(sizeof(int)))
    self.heap = true
end


local test = require "test"

printtestheader("raii-unique_ptr.t: test return ptr value from function before resource is deleted")
terra testdereference()
    var ptr : A
    ptr:allocate()
    ptr:setvalue(3)
    return ptr:getvalue()
end
test.eq(testdereference(), 3)

terra returnheapresource()
    var ptr : A
    ptr:allocate()
    ptr:setvalue(3)
    return ptr
end

printtestheader("raii-unique_ptr.t: test return heap resource from function")
terra testgetptr()
    var ptr = returnheapresource()
    return ptr:getvalue()
end
test.eq(testgetptr(), 3)


