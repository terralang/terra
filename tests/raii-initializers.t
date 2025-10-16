require "terralibext"  --load 'terralibext' to enable raii

local test = require("test")

local function printtestheader(s)
    print()
    print("===========================")
    print(s)
    print("===========================")
end

local struct A {
    x : int
    y : int
    z : int
    ptr : &int
}

terra A:__dtor()
    self.x = -1
    self.y = -1
    self.z = -1
    self.ptr = nil
end

printtestheader("partial initialization - input as tuple")

terra main()
    var a : A = A{1,2,3}
    if a.ptr == nil then
        return 1
    else
        return 2
    end
end
test.eq(main(), 1)

printtestheader("partial initialization - input as named struct")

terra main2()
    var a : A = A{y=2,z=3,x=1}
    if a.x==1 and a.y==2 and a.z==3 and a.ptr == nil then
        return true
    end
end
test.eq(main2(), true)

printtestheader("initialization - with move from other struct")

local struct B{
    a : A
}

terra main3()
    var a : A = A{y=2,z=3,x=1}
    a.ptr = &a.x
    var b : B = B{__move__(a)}
    if a.ptr==nil and b.a.ptr==&a.x then
        return true
    end
end
test.eq(main3(), true)


printtestheader("initialization - tuple and named initialization - counting constructors")

local struct C{
    x : int
    y : int
    z : int
    p : &int
}

terra C:__dtor()
    self.x = -1
    self.y = -1
    self.z = -1
    self.p = nil
end

local function countconstructors(typ)
    local count = 0
    for k,v in pairs(typ.constructor) do
        count = count + 1
    end
    return count
end

terra main4()
    var c = C{x=1}
    var d = C{1}
end
main4()
test.eq(countconstructors(C), 1)

C.constructors = {}
terra main5()
    var c = C{x=1}
    var d = C{1}
    var e = C{x=1, y=2}
    var f = C{1, 2}
end
main5()
test.eq(countconstructors(C), 2)

C.constructors = {}
terra main6()
    var c = C{x=1}              --calling imp-1
    var d = C{1}                --calling imp-1
    var e = C{x=1, y=2}         --calling imp-2
    var f = C{1, 2}             --calling imp-2
    var g = C{z=1, y=2, x=1}    --calling imp-3
    var h = C{1, 2, 1}          --calling imp-4
end
main6()
test.eq(countconstructors(C), 4)