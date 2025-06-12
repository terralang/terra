if not require("fail") then return end
require "terralibext"   --load 'terralibext' to enable raii

local std = {}
std.io = terralib.includec("stdio.h")


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
    std.io.printf("__copy: calling custom copy.\n")
    to.data = from.data+1
end

terra test0()
    var a = A{1}
    var b = A{2}
    a, b = b, a
    --tuple assignments are prohibited when __copy is implemented
    --because proper resource management cannot be guaranteed
    --(at least not yet)
    return a.data, b.data
end
test0()