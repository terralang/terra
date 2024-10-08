require "terralibext"           --load 'terralibext' to enable raii
local test = require "test"

local std = {
    io = terralib.includec("stdio.h")
}

local function printtestheader(s)
    print()
    print("===========================")
    print(s)
    print("===========================")
end

struct A{
    data : int
}

A.methods.__init = terra(self : &A)
    std.io.printf("__init: calling initializer.\n")
    self.data = 1
end

A.methods.__dtor = terra(self : &A)
    std.io.printf("__dtor: calling destructor.\n")
    self.data = -1
end

A.methods.__copy = terralib.overloadedfunction("__copy")
A.methods.__copy:adddefinition(terra(from : &A, to : &A)
    std.io.printf("__copy: calling copy assignment {&A, &A} -> {}.\n")
    to.data = from.data + 10
end)
A.methods.__copy:adddefinition(terra(from : int, to : &A)
    std.io.printf("__copy: calling copy assignment {int, &A} -> {}.\n")
    to.data = from
end)
A.methods.__copy:adddefinition(terra(from : &A, to : &int)
    std.io.printf("__copy: calling copy assignment {&A, &int} -> {}.\n")
    @to = from.data
end)


printtestheader("raii.t - testing __init metamethod")
terra testinit()
    var a : A
    return a.data
end
test.eq(testinit(), 1)

printtestheader("raii.t - testing __dtor metamethod")
terra testdtor()
    var x : &int
    do
        var a : A
        x = &a.data
    end
    return @x
end
test.eq(testdtor(), -1)

printtestheader("raii.t - testing __copy metamethod in copy-construction")
terra testcopyconstruction()
    var a : A
    var b = a
    return b.data
end
test.eq(testcopyconstruction(), 11)

printtestheader("raii.t - testing __copy metamethod in copy-assignment")
terra testcopyassignment()
    var a : A
    a.data = 2
    var b : A
    b = a
    return b.data
end
test.eq(testcopyassignment(), 12)

printtestheader("raii.t - testing __copy metamethod in copy-assignment from integer to struct.")
terra testcopyassignment1()
    var a : A
    a = 3
    return a.data
end
test.eq(testcopyassignment1(), 3)

printtestheader("raii.t - testing __copy metamethod in copy-assignment from struct to integer.")
terra testcopyassignment2()
    var a : A
    var x : int
    a.data = 5
    x = a
    return x
end
test.eq(testcopyassignment2(), 5)