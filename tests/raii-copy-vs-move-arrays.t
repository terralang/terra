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

local ninitcalls = global(int)
local ncopycalls = global(int)
local nmovecalls = global(int)
local ndtorcalls = global(int)

local getninitcalls = terra() return ninitcalls end
local getncopycalls = terra() return ncopycalls end
local getnmovecalls = terra() return nmovecalls end
local getndtorcalls = terra() return ndtorcalls end

struct A{
    data : int
}

A.methods.__init = terra(self : &A)
    ninitcalls = ninitcalls + 1
    self.data = 1
end

A.methods.__dtor = terra(self : &A)
    ndtorcalls = ndtorcalls + 1
    self.data = -1
end

A.methods.__move = terra(from : &A, to : &A)
    nmovecalls = nmovecalls + 1
    to.data = from.data
    from.data = -1
end

-----------------------------------------------------------
--First we test array moving
-----------------------------------------------------------

printtestheader("raii-copyctr.t - move-construction for arrays")

terra test1()
    ninitcalls, nmovecalls, ncopycalls, ndtorcalls = 0, 0, 0, 0
    var a : A[3] --initialized to {1,1,1}
    var b = a --initialized to {1,1,1} and adds `a`
    return b[0].data+b[1].data+b[2].data --1+1+1=3
end
test.eq(test1(), 3)
--test that the array move runs, which means A.methods.__move is called 3 times
test.eq(getnmovecalls(), 3)
test.eq(getncopycalls(), 0)
test.eq(getninitcalls(), 6)
test.eq(getndtorcalls(), 6)

printtestheader("raii-copyctr.t - move-assignment for arrays")

terra test2()
    ninitcalls, nmovecalls, ncopycalls, ndtorcalls = 0, 0, 0, 0
    var a : A[3] --initialized to {1,1,1}
    var b : A[3] --initialized to {1,1,1}
    b = a --move a to b
    return b[0].data+b[1].data+b[2].data --1+1+1=3
end
test.eq(test2(), 3)
--test that the array move runs, which means A.methods.__move is called 3 times
test.eq(getnmovecalls(), 3)
test.eq(getncopycalls(), 0)
test.eq(getninitcalls(), 6)
test.eq(getndtorcalls(), 6)

printtestheader("raii-copyctr.t - move-construction for arrays-of-arrays")

terra test3()
    ninitcalls, nmovecalls, ncopycalls, ndtorcalls = 0, 0, 0, 0
    var a : A[3][2] --initialized to {1,1,1}
    var b = a
    return b[0][0].data+b[0][1].data+b[0][2].data+b[1][0].data+b[1][1].data+b[1][2].data --1+1+1+1+1+1=6
end
test.eq(test3(), 6)
test.eq(getnmovecalls(), 6)
test.eq(getncopycalls(), 0)
test.eq(getninitcalls(), 12)
test.eq(getndtorcalls(), 12)


printtestheader("raii-copyctr.t - move-assignment for arrays-of-arrays")

terra test4()
    ninitcalls, nmovecalls, ncopycalls, ndtorcalls = 0, 0, 0, 0
    var a : A[3][2] --initialized to {1,1,1}
    var b : A[3][2] --initialized to {1,1,1}
    b = a --adds a+{1,1,1}
    return b[0][0].data+b[0][1].data+b[0][2].data+b[1][0].data+b[1][1].data+b[1][2].data --1+1+1+1+1+1=6
end
test.eq(test4(), 6)
test.eq(getnmovecalls(), 6)
test.eq(getncopycalls(), 0)
test.eq(getninitcalls(), 12)
test.eq(getndtorcalls(), 12)


printtestheader("raii-copyctr.t - pass array by value")

--take an array by value
local f = terra(arr : A[3])
    return arr
end

terra test5()
    ninitcalls, nmovecalls, ncopycalls, ndtorcalls = 0, 0, 0, 0
    var a : A[3] --initialized to {1,1,1}
    var b = f(a) --a move happens here
    return b[0].data+b[1].data+b[2].data --1+1+1=3
end
test.eq(test5(), 3)
test.eq(getnmovecalls(), 3)
test.eq(getncopycalls(), 0)
test.eq(getninitcalls(), 6)
test.eq(getndtorcalls(), 6)

-----------------------------------------------------------
--Now we implement the __copy method and test array copying
-----------------------------------------------------------

A.methods.__copy = terra(from : &A, to : &A)
    ncopycalls = ncopycalls + 1
    to.data = from.data + 1
end

printtestheader("raii-copyctr.t - copy-construction for arrays")

terra test6()
    ninitcalls, nmovecalls, ncopycalls, ndtorcalls = 0, 0, 0, 0
    var a : A[3] --initialized to {1,1,1}
    var b = a --initialized to {1,1,1} and adds `a`
    return b[0].data+b[1].data+b[2].data --2+2+2=6
end
test.eq(test6(), 6)
--test that the array copier runs, which means A.methods.__copy is called 3 times
test.eq(getnmovecalls(), 0)
test.eq(getncopycalls(), 3)
test.eq(getninitcalls(), 6)
test.eq(getndtorcalls(), 6)

printtestheader("raii-copyctr.t - copy-assignment for arrays")

terra test7()
    ninitcalls, nmovecalls, ncopycalls, ndtorcalls = 0, 0, 0, 0
    var a : A[3] --initialized to {1,1,1}
    var b : A[3] --initialized to {1,1,1}
    b = a --adds a+{1,1,1}
    return b[0].data+b[1].data+b[2].data --2+2+2=6
end
test.eq(test7(), 6)
--test that the array copier runs, which means A.methods.__copy is called 3 times
test.eq(getnmovecalls(), 0)
test.eq(getncopycalls(), 3)
test.eq(getninitcalls(), 6)
test.eq(getndtorcalls(), 6)

printtestheader("raii-copyctr.t - overriding copy- by move-assignment for arrays")

terra test8()
    ninitcalls, nmovecalls, ncopycalls, ndtorcalls = 0, 0, 0, 0
    var a : A[3] --initialized to {1,1,1}
    var b : A[3] --initialized to {1,1,1}
    b = __move__(a) --adds a+{1,1,1}
    return b[0].data+b[1].data+b[2].data --1+1+1=3
end
test.eq(test8(), 3)
--test that the array copier runs, which means A.methods.__copy is called 3 times
test.eq(getnmovecalls(), 3)
test.eq(getncopycalls(), 0)
test.eq(getninitcalls(), 6)
test.eq(getndtorcalls(), 6)


-----------------------------------------------------------
--Testing arrays-of-arrays
-----------------------------------------------------------

printtestheader("raii-copyctr.t - copy-construction for arrays-of-arrays")

terra test9()
    ninitcalls, nmovecalls, ncopycalls, ndtorcalls = 0, 0, 0, 0
    var a : A[3][2] --initialized to {1,1,1}
    var b = a
    return b[0][0].data+b[0][1].data+b[0][2].data+b[1][0].data+b[1][1].data+b[1][2].data --2+2+2+2+2+2=12
end
test.eq(test9(), 12)
test.eq(getnmovecalls(), 0)
test.eq(getncopycalls(), 6)
test.eq(getninitcalls(), 12)
test.eq(getndtorcalls(), 12)

printtestheader("raii-copyctr.t - copy-assignment for arrays-of-arrays")

terra test10()
    ninitcalls, nmovecalls, ncopycalls, ndtorcalls = 0, 0, 0, 0
    var a : A[3][2] --initialized to {1,1,1}
    var b : A[3][2] --initialized to {1,1,1}
    b = a --adds a+{1,1,1}
    return b[0][0].data+b[0][1].data+b[0][2].data+b[1][0].data+b[1][1].data+b[1][2].data --2+2+2+2+2+2=12
end
test.eq(test10(), 12)
test.eq(getnmovecalls(), 0)
test.eq(getncopycalls(), 6)
test.eq(getninitcalls(), 12)
test.eq(getndtorcalls(), 12)

printtestheader("raii-copyctr.t - pass array by value - copy-assignment")

--take an array by value
local g = terra(arr : A[3])
    return arr
end

terra test11()
    ninitcalls, nmovecalls, ncopycalls, ndtorcalls = 0, 0, 0, 0
    var a : A[3] --initialized to {1,1,1}
    var b = g(a) --a copy happens here
    return b[0].data+b[1].data+b[2].data --2+2+2=6
end
test.eq(test11(), 6)
test.eq(getnmovecalls(), 0)
test.eq(getncopycalls(), 3)
test.eq(getninitcalls(), 6)
test.eq(getndtorcalls(), 6)

printtestheader("raii-copyctr.t - pass array-of-arrays by value - copy-assignment")

--take an array by value
local h = terra(arr : A[3][1])
    return arr
end

terra test12()
    ninitcalls, nmovecalls, ncopycalls, ndtorcalls = 0, 0, 0, 0
    var a : A[3][1] --initialized to {1,1,1}
    var b = h(a) --a copy happens here
    return b[0][0].data+b[0][1].data+b[0][2].data --2+2+2=6
end
test.eq(test12(), 6)
test.eq(getnmovecalls(), 0)
test.eq(getncopycalls(), 3)
test.eq(getninitcalls(), 6)
test.eq(getndtorcalls(), 6)

printtestheader("raii-copyctr.t - pass array-of-arrays by value - move-assignment")

terra test12()
    ninitcalls, nmovecalls, ncopycalls, ndtorcalls = 0, 0, 0, 0
    var a : A[3][1] --initialized to {1,1,1}
    var b = h(__move__(a)) --a copy happens here
    return b[0][0].data+b[0][1].data+b[0][2].data --1+1+1=3
end
test.eq(test12(), 3)
test.eq(getnmovecalls(), 3)
test.eq(getncopycalls(), 0)
test.eq(getninitcalls(), 6)
test.eq(getndtorcalls(), 6)


printtestheader("raii-copyctr.t - index array copy-assignment")

terra test13()
    ninitcalls, nmovecalls, ncopycalls, ndtorcalls = 0, 0, 0, 0
    var a : A[3] --initialized to {1,1,1}
    var b = a[0] --a copy happens here
    return b.data --1+1=2
end
test.eq(test13(), 2)
test.eq(getnmovecalls(), 0)
test.eq(getncopycalls(), 1)
test.eq(getninitcalls(), 4)
test.eq(getndtorcalls(), 4)

printtestheader("raii-copyctr.t - index array move-assignment")

terra test14()
    ninitcalls, nmovecalls, ncopycalls, ndtorcalls = 0, 0, 0, 0
    var a : A[3] --initialized to {1,1,1}
    var b = __move__(a[0]) --a copy happens here
    return b.data --1=1
end
test.eq(test14(), 1)
test.eq(getnmovecalls(), 1)
test.eq(getncopycalls(), 0)
test.eq(getninitcalls(), 4)
test.eq(getndtorcalls(), 4)