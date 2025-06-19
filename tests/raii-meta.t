require "terralibext"           --load 'terralibext' to enable raii

local test = require "test"
local io = terralib.includec("stdio.h")

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
    io.printf("__init: calling initializer.\n")
    self.data = 1
end

local nglobal = global(int)

local getn = terra()
    return nglobal
end

A.methods.__dtor = terra(self : &A)
    io.printf("__dtor: calling destructor.\n")
    self.data = -1
    nglobal = nglobal + 1
end

A.methods.__copy = terra(from : &A, to : &A)
    io.printf("__copy: calling copy assignment {&A, &A} -> {}.\n")
    to.data = from.data
end

printtestheader("raii-meta.t - testing __dtor in macro 'letin' block")

local genobj = macro(function()
    return quote
        var x : A --x is returned, assigned to y in the outer scope, y takes control and
        --y:__dtor() should be called
        x.data = 5
        var z : A --z is not returned, defer z:__dtor() needs to be called
    in
        x
    end
end)

terra main()
    nglobal = 0
    var y = genobj()
    return getn()
end
test.eq(main(), 0)
test.eq(getn(), 2)

printtestheader("raii-meta.t - testing __dtor in macro 'letin' block returning reference")

local genref = macro(function()
    return quote
        var x : A --reference to x is returned, defer x:__dtor() needs to be called
        x.data = 5
        var z : A --z is not returned, defer z:__dtor() needs to be called
    in
        &x
    end
end)

terra main1()
    nglobal = 0
    var y = genref()
    return getn()
end
test.eq(main1(), 0)
test.eq(getn(), 2)

printtestheader("raii-meta.t - testing __dtor in macro 'letin' block with a handle to a managed variable.")

local genhandle = macro(function()
    return quote
        var x : A
        var z = __handle__(x) --provides a handle to x, no __dtor is called
    in
        x
    end
end)

terra main2()
    nglobal = 0
    var y = genhandle()
    return getn()
end
test.eq(main2(), 0)
test.eq(getn(), 1)
