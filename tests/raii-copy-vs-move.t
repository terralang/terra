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

terra A:__dtor()
    self.data = -1
end

--passing by value, so move-assignment is performed on both 'a' and 'b'
--increasing 'a.data' and 'b.data' by one
terra myfun(a : A, b : A)
    return a.data + b.data
end

printtestheader("raii-move-assignment.t - testing __move")

--__copy is not implemented, so default to __move
terra main()
    var a : A
    a.data = 2
    var b : A
    b.data = 2
    var s = myfun(a, b) --'a' is moved from, 'b' is moved from, --> s = 2 + 2
    return s + a.data --'a' has been moved from, so its __init has been called --> a.data = 1
end
test.eq(main(), 5)


printtestheader("raii-move-assignment.t - testing __copy when passing by value")

terra A.methods.__copy(from: &A, to: &A)
    to.data = from.data + 1
end

--__copy is implemented, so 'a' and 'b' will be consumed by 'myfun' using a __copy
terra main1()
    var a : A --a.data = 1
    var b : A --b.data = 1
    return myfun(a, b) --copy-assignment is performed for 'a' and 'b', so myfun returns 4
end
test.eq(main1(), 4)


printtestheader("raii-move-assignment.t - testing __move when passing by value")

--forcefully __move 'a'
terra main2()
    var a : A
    a.data = 2  --a.data = 2
    var b : A --b.data = 1
    var s = myfun(__move__(a), b) --'a' is moved from, 'b' is copied, --> s = 2 + 2
    return s + a.data --'a' has been moved from, so its __init has been called --> a.data = 1
end
test.eq(main2(), 5)


printtestheader("raii-move-assignment.t - testing __copy assignment")

terra main3()
    var a : A
    a.data = 3
    var b = a --here we are calling __copy --> b.data = 4, a.data = 3
    return a.data + b.data
end
test.eq(main3(), 7)

printtestheader("raii-move-assignment.t - testing __move assignment")

terra main4()
    var a : A
    a.data = 3
    var b = __move__(a) --here we are calling the generated __move --> b.data = 3, a.data = 1
    return a.data + b.data
end
test.eq(main4(), 4)

printtestheader("raii-move-assignment.t - testing __move from macro")

local fromusingmove = macro(function(data)
    return quote
        var a : A
        a.data = data
    in
        a --a is moved from by default
    end
end)

terra main6()
    var a = fromusingmove(5) --macros act like functions: __copy is not called
    return a.data
end
test.eq(main6(), 5)

printtestheader("raii-move-assignment.t - testing __move, __copy, and bitcopy")

terra main7(k : int)
    var a : A
    a.data = 3
    if k == 0 then
        var b = a --__copy is called --> b.data = 3+1
        return a.data + b.data --> 7
    elseif k == 1 then
        var b = __move__(a) --__move is called --> a.data = 1 and b.data = 3
        return a.data + b.data --> 4
    end
end
test.eq(main7(0), 7)
test.eq(main7(1), 4)