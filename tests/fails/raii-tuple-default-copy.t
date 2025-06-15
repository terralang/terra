if not require("fail") then return end
require "terralibext"   --load 'terralibext' to enable raii
local test = require "test"

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

terra test0()
    var a = A{1}
    var b = A{2}
    a, b = b, a --bitcopies don't work in a swap
    --tuple assignments are prohibited because proper
    --resource management cannot be guaranteed
    --(at least not yet)
    return a.data, b.data
end
test0()