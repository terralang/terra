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
    If the method is not implemented for the exact types then a (user-defined)
    implicit cast should be attempted.
--]]

local test = require("test")
local std = {
    io = terralib.includec("stdio.h")
}

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

A.methods.__copy = terra(from : &A, to : &A)
    std.io.printf("__copy: calling copy assignment {&A, &A} -> {}.\n")
    to.data = to.data + from.data + 10
end

A.metamethods.__cast = function(from, to, exp)
    print("attempting cast from "..tostring(from).." --> "..tostring(to))
    if to == &A and from:ispointer() then
        return quote
                var tmp = A{@exp}
            in
                &tmp
            end
    end
end

--[[
    The integer '2' will first be cast to a temporary of type A using
    the user defined A.metamethods.__cast method. Then the method
    A.methods.__init(self : &A) is called to initialize the variable
    and then the copy-constructor A.methods.__copy(from : &A, to : &A)
    will be called to finalize the copy-construction.
--]]
terra testwithcast()
    var a : A = 2
    return a.data
end

-- to.data + from.data + 10 = 1 + 2 + 10 = 13
test.eq(testwithcast(), 13)


A.methods.__copy = terralib.overloadedfunction("__copy")

A.methods.__copy:adddefinition(terra(from : &A, to : &A)
    std.io.printf("__copy: calling copy assignment {&A, &A} -> {}.\n")
    to.data = to.data + from.data + 10
end)

A.methods.__copy:adddefinition(terra(from : int, to : &A)
    std.io.printf("__copy: calling copy assignment {int, &A} -> {}.\n")
    to.data = to.data + from + 11
end)

--[[
    The method A.methods.__init(self : &A) is called to initialize the variable 
    and then the copy-constructor A.methods.__copy(from : int, to : &A) will be 
    called to finalize the copy-construction.
--]]
terra testwithoutcast()
    var a : A = 2
    return a.data
end
-- to.data + from.data + 10 = 1 + 2 + 11 = 14
test.eq(testwithoutcast(), 14)