local std = {}
std.io = terralib.includec("stdio.h")

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


terra testinit()
    var a : A
    return a.data
end

terra testdtor()
    var x : &int
    do
        var a : A
        x = &a.data
    end
    return @x
end

terra testcopyconstruction()
    var a : A
    var b = a
    return b.data
end

terra testcopyassignment()
    var a : A
    a.data = 2
    var b : A
    b = a
    return b.data
end

terra testcopyassignment1()
    var a : A
    a = 3
    return a.data
end

terra testcopyassignment2()
    var a : A
    var x : int
    a.data = 5
    x = a
    return x
end

local test = require "test"

--test if __init is called on object initialization to set 'a.data = 1'
printtestheader("raii.t - testing __init metamethod")
test.eq(testinit(), 1)

--test if __dtor is called at the end of the scope to set 'a.data = -1'
printtestheader("raii.t - testing __dtor metamethod")
test.eq(testdtor(), -1)

--test if __copy is called in construction 'var b = a'
printtestheader("raii.t - testing __copy metamethod in copy-construction")
test.eq(testcopyconstruction(), 11)

--test if __copy is called in an assignment 'b = a'
printtestheader("raii.t - testing __copy metamethod in copy-assignment")
test.eq(testcopyassignment(), 12)

--test if __copy is called in an assignment 'a = 3'
printtestheader("raii.t - testing __copy metamethod in copy-assignment from integer to struct.")
test.eq(testcopyassignment1(), 3)

--test if __copy is called in an assignment 'x = a' for integer x
printtestheader("raii.t - testing __copy metamethod in copy-assignment from struct to integer.")
test.eq(testcopyassignment2(), 5)