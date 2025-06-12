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

local function printtestheader(s)
    print()
    print("===========================")
    print(s)
    print("===========================")
end


local test = require("test")
local io = terralib.includec("stdio.h")

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

ncopycalls = global(int)

terra getncopycalls()
    return ncopycalls
end

A.methods.__copy = terra(from : &A, to : &A)
    ncopycalls = ncopycalls + 1
    io.printf("__copy: calling copy assignment {&A, &A} -> {}.\n")
    to.data = from.data + 1
end

printtestheader("raii-copyctr.t - copy-construction")

terra test1()
    var a : A           --__init -> a.data = 1
    var aa = a          --__init + __copy -> a.data = 2
    return aa.data
end
test.eq(test1(), 2)


printtestheader("raii-copyctr.t - copy-construction with generated __ctor")

--since A is managed, an __init, __dtor, and __copy will
--be generated
struct B{
    data : A
}
B.generate_initializers = true

-- terra test2()
--     var a : A           --__init -> a.data = 1
--     var b = B{a}        --__init + copy assignment (for `a`) --> b.data.data = 2
--     return b.data.data
-- end
-- test2:printpretty()
-- test.eq(test2(), 2)


printtestheader("raii-copyctr.t - copy-construction in passing parameters by value to function")

--passing by value, so copy-assignment is performed on both 'a' and 'b'
--increasing 'a.data' and 'b.data' by one
terra myfun(a : A, b : A)
    return a.data + b.data
end

terra test3()
    var a : A --a.data = 1
    var b : A --b.data = 1
    return myfun(a, b) --copy-assignment is performed for 'a' and 'b', so myfun returns 4
end
test.eq(test3(), 4)


printtestheader("raii-copyctr.t - copy-construction for arrays")

terra test4()
    ncopycalls = 0
    var a : A[3] --initialized to {1,1,1}
    var b = a --initialized to {1,1,1} and adds `a`
    return b[0].data+b[1].data+b[2].data --2+2+2=6
end
test.eq(test4(), 6)
--test that the array copier runs, which means A.methods.__copy is called 3 times
test.eq(getncopycalls(), 3)

printtestheader("raii-copyctr.t - copy-assignment for arrays")

terra test5()
    ncopycalls = 0
    var a : A[3] --initialized to {1,1,1}
    var b : A[3] --initialized to {1,1,1}
    b = a --adds a+{1,1,1}
    return b[0].data+b[1].data+b[2].data --2+2+2=6
end
test.eq(test5(), 6)
--test that the array copier runs, which means A.methods.__copy is called 3 times
test.eq(getncopycalls(), 3)