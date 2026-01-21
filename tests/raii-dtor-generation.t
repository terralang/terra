require "terralibext"  --load 'terralibext' to enable raii

local test = require("test")

local function printtestheader(s)
    print()
    print("===========================")
    print(s)
    print("===========================")
end

local struct A {
    data : int
}

printtestheader("raii-dtor-generation.t - testing __dtor generation")

terralib.ext.addmissing.__dtor(A)
test.eq(A.methods.__dtor, nil)
test.eq(A.__dtor_generated, true)

terra A:__dtor()
    self.data = -1
end

local struct B{
    a : A
    b : &A
}

local struct C{
    a : A
    b : B
    p : &int
    i : int
    z : int[3]
    q : A[2]
    v : bool
}

terralib.ext.addmissing.__init(C)
terralib.ext.addmissing.__dtor(C)

--check if a global is correctly initialized and destroyed
local c = global(C)
terra cdtor()
    c:__init()
    c:__dtor()
end
cdtor()

terra geta() return c.a.data end
terra getb0() return c.b.a.data end
terra getb1() return c.b.b end
terra getp() return c.p end
terra getq(i : int) return c.q[i].data end

printtestheader("raii-dtor-generation.t - testing recursive __dtor generation")

test.eq(geta(), -1)
test.eq(getb0(), -1)
test.eq(getb1(), nil)
test.eq(getp(), nil)
test.eq(getq(0), -1)
test.eq(getq(1), -1)