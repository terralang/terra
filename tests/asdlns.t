
local asdl = require("asdl")
local C = asdl.NewContext()

C:Define [[
    module A {
        B = C(number n, E e, B b, N.What nwhat)
            | D
    }
    E = (number a)
    Z = (A.B ab, A.D ad)
    module N {
        What = ()
    }
]]

print(C.A.C(1,C.E(4),C.A.D,C.N.What()))