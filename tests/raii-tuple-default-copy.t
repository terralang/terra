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

printtestheader("raii.t - testing default copy metamethod")
terra test0()
    var a = A{1}
    var b = A{2}
    a, b = b, a --bitcopies should work in a swap
    --the following code is generated
    --var tmp_a = __move(b)     --store evaluated rhs in a tmp variable
    --var tmp_b = __move(a)     --store evaluated rhs in a tmp variable
    --a:__dtor()                --delete old memory (nothing happens as 'a' has been moved from)
    --b:__dtor()                --delete old memory (nothing happens as 'a' has been moved from)
    --a = __move(tmp_a)         --move new data into 'a'
    --b = __move(tmp_b)         --move new data into 'b'
    return a.data, b.data
end
test.meq({2, 1}, test0())