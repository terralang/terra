require "terralibext"  --load 'terralibext' to enable raii
--[[
    We need that direct initialization
        var a : A = b
    yields the same result as
        var a : A
        a = b
    If 'b' is a variable or a literal (something with a value) and the user has
    implemented the right copy-assignment 'A.methods.__copy' then the copy
    should be performed using this method.
--]]

local test = require("test")
io = terralib.includec("stdio.h")

struct A{
    data : int
}

A.methods.__init = terra(self : &A)
    io.printf("__init: calling initializer.\n")
    self.data = 1
end

A.methods.__dtor = terra(self : &A)
    io.printf("__dtor: calling destructor.\n")
    self.data = -1
end

A.methods.__copy = terra(from : &A, to : &A)
    io.printf("__copy: calling copy assignment {&A, &A} -> {}.\n")
    to.data = to.data + from.data + 1
end

terra test1()
    var a : A           --__init -> a.data = 1
    var aa = a          --__init + __copy -> a.data = 3
    return aa.data
end

-- aa.data = aa.data + a.data + 1 = 3
test.eq(test1(), 3)

--since A is managed, an __init, __dtor, and __copy will
--be generated
struct B{
    data : A
}

terra test2()
    var a : A           --__init -> a.data = 1
    var b = B{a}        --__init + __copy -> b.data.data = 3
    return b.data.data
end

-- b.data.data = b.data.data + a.data + 1 = 3
test.eq(test2(), 3)