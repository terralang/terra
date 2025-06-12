require "terralibext"           --load 'terralibext' to enable raii

local test = require("test")
local io = terralib.includec("stdio.h")

local function printtestheader(s)
    print()
    print("===========================")
    print(s)
    print("===========================")
end

local struct A {
    data : int
}

terra A:__init()
    self.data = 1
end

A.methods.__copy = terralib.overloadedfunction("__copy",{
    terra(from: &int, to: &A)
        to.data = to.data + @from
    end
    ,
    terra(from: &A, to: &A)
        to.data = from.data
    end
})

ndestructorcalls = global(int)

terra getndestructorcalls()
    return ndestructorcalls
end

terra A:__dtor()
    self.data = self.data + 1
    ndestructorcalls = ndestructorcalls + 1
end

printtestheader("raii-dtor.t - testing __dtor pass by value")

terra mytest0(a : A)
end
mytest0:printpretty()
terra main0()
    ndestructorcalls = 0
    var a : A
    mytest0(a)
    return getndestructorcalls()
end
test.eq(main0(), 1)
test.eq(getndestructorcalls(), 2)

printtestheader("raii-dtor.t - testing __dtor pass by value - 2")

terra mytest1(a : A)
    while true do
        if a.data == 2 then
            break
        end
        a.data = a.data + 1
    end
end
mytest1:printpretty()
terra main1()
    ndestructorcalls = 0
    var a : A
    mytest1(a)
    return getndestructorcalls()
end
main1:printpretty()
test.eq(main1(), 1)
test.eq(getndestructorcalls(), 2)

terra mytest(b : A)
    var x : A       --x.data == 1
    if b.data == 10 then
        x = 7       --x.data==1+7
        return x.data
    elseif b.data == 2 then
        x = -7      --x.data==1-7
        return x.data
    end
    x = 1 --x.data==1+1
    return x.data
end

terra main(v : int)
    ndestructorcalls = 0
    var z : A       --z.data==1
    z = v      --z.data==1+v
    var t = mytest(z)
    return t + getndestructorcalls()
end

printtestheader("raii-dtor.t - testing __dtor nested scopes - if-branch 1")

--if-branch
test.eq(main(9), 10)
test.eq(getndestructorcalls(), 3) --__dtor is called 3 times in total


printtestheader("raii-dtor.t - testing __dtor nested scopes - if-branch 2")

--elseif branch
test.eq(main(1), -4)
test.eq(getndestructorcalls(), 3) --__dtor is called 3 times in total

printtestheader("raii-dtor.t - testing __dtor nested scopes - if-branch 3")

--main branch
test.eq(main(2), 4)
test.eq(getndestructorcalls(), 3) --__dtor is called 3 times in total


--test nested scopes and proper destructor calls after return statement
terra main2(v : int)
    ndestructorcalls = 0
    var z : A
    --z:__init()    --z.data==1
    z = v           --replaced by: A.methods.__copy(&v, &z) ---> z.data==1+v
    while z.data < 10 do
        var y : A
        --y:__init()    --y.data==1
        if z.data == 5 then
            var x : A
            --x:__init()    --x.data==1
            --defer x:__dtor()
            --defer y:__dtor()
            --defer z:__dtor()
            return getndestructorcalls()
        end
        z.data = z.data + 1
        --defer y:__dtor()
    end
    --defer z:__dtor()
    return getndestructorcalls()
end

printtestheader("raii-dtor.t - testing __dtor nested scopes - while-loop -branch 1")

--exit through inner scope - if-statement
test.eq(main2(2), 2) --z.data = 3, increased in while-loop until 5, and then return via if-statement
test.eq(getndestructorcalls(), 5) --__dtor is called 3 times in if-statement

printtestheader("raii-dtor.t - testing __dtor nested scopes - while-loop -branch 1 - direct")

--direct exit through inner scope - if-statement
test.eq(main2(4), 0) --z.data = 5, increased in while-loop until 5, and then return via if-statement
test.eq(getndestructorcalls(), 3) --__dtor is called 3 times in if-statement

printtestheader("raii-dtor.t - testing __dtor nested scopes - while-loop -branch 2")

--exit through through outer-most scope after finishing while-loop
test.eq(main2(5), 4) --z.data = 6, increased in while-loop until 10, exit loop and exit main2
test.eq(getndestructorcalls(), 5) --__dtor is called 4 times in while-loop and once in main2


--test nested scopes and proper destructor calls after break statement
terra main3(v : int)
    ndestructorcalls = 0
    var a : A
    --a:__init()
    a = v -- replaced by: A.methods.__copy(&v, &a) -- a.data = 1 + v
    while true do
        var b : A --b is not released the second time
        --b:__init()
        if a.data > 2 then
            var d : A
            --d:__init()
            var e : A
            --e:__init()
            --defer d:__dtor()
            --defer e:__dtor()
            --defer b:__dtor()
            break
        end
        var c : A
        --c:__init()
        a.data = a.data + 1
        --defer b:__dtor()
        --defer c:__dtor()
    end
    --defer a:__dtor()
    return getndestructorcalls()
end

main3:printpretty()

printtestheader("raii-dtor.t - testing __dtor nested scopes with 'break'")

test.eq(main3(0), 7)
test.eq(getndestructorcalls(), 8)

test.eq(main3(1), 5)
test.eq(getndestructorcalls(), 6)


printtestheader("raii-dtor.t - testing arraydestructor")

terra main4()
    ndestructorcalls = 0
    var a : A[4]
    return getndestructorcalls()
end
test.eq(main4(), 0)
test.eq(getndestructorcalls(), 4)


printtestheader("raii-dtor.t - testing tuple destructor")
--tuples are just structs, so this should work without any
--special work

local S = tuple(A, A)

terra main5()
    ndestructorcalls = 0
    var a : S
    return getndestructorcalls()
end
test.eq(main5(), 0)
test.eq(getndestructorcalls(), 2)

