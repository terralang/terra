--load 'terralibext' to enable raii
require "terralibext"

local test = require "test"

local function printtestheader(s)
    print()
    print("===========================")
    print(s)
    print("===========================")
end

local std = {
    io  = terralib.includec("stdio.h")
}

--A is a managed struct, as it implements __init, __copy, __dtor
local struct A{
    data : int
}

A.methods.__init = terra(self : &A)
    std.io.printf("A.__init\n")
    self.data = 1
end

A.methods.__dtor = terra(self : &A)
    std.io.printf("A.__dtor\n")
    self.data = -1
end

A.methods.__copy = terra(from : &A, to : &A)
    std.io.printf("A.__copy\n")
    to.data = from.data + 2
end

local struct B{
    data : int
}

local struct C{
    data_a : A --managed
    data_b : B --not managed
}

local struct D{
    data_a : A --managed
    data_b : B --not managed
    data_c : C
}

printtestheader("raii-compose.t - testing __init for managed struct")
local terra testinit_A()
    var a : A
    return a.data
end
test.eq(testinit_A(), 1)

printtestheader("raii-compose.t - testing __init for managed field")
local terra testinit_C()
    var c : C
    return c.data_a.data
end
test.eq(testinit_C(), 1)

printtestheader("raii-compose.t - testing __init for managed field and subfield")
local terra testinit_D()
    var d : D
    return d.data_a.data + d.data_c.data_a.data
end
test.eq(testinit_D(), 2)

printtestheader("raii-compose.t - testing __dtor for managed struct")
local terra testdtor_A()
    var x : &int
    do
        var a : A
        x = &a.data
    end
    return @x
end
test.eq(testdtor_A(), -1)

printtestheader("raii-compose.t - testing __dtor for managed field")
local terra testdtor_C()
    var x : &int
    do
        var c : C
        x = &c.data_a.data
    end
    return @x
end
test.eq(testdtor_C(), -1)

printtestheader("raii-compose.t - testing __dtor for managed field and subfield")
local terra testdtor_D()
    var x : &int
    var y : &int
    do
        var d : D
        x = &d.data_a.data
        y = &d.data_c.data_a.data
    end
    return @x + @y
end
test.eq(testdtor_D(), -2)

printtestheader("raii-compose.t - testing __copy for managed field")
terra testcopyassignment_C()
    var c_1 : C
    var c_2 : C
    c_1.data_a.data = 5
    c_2 = c_1
    std.io.printf("value c_2._data_a.data %d\n", c_2.data_a.data)
    return c_2.data_a.data
end
test.eq(testcopyassignment_C(), 5 + 2)

printtestheader("raii-compose.t - testing __copy for managed field and subfield")
terra testcopyassignment_D()
    var d_1 : D
    var d_2 : D
    d_1.data_a.data = 5
    d_1.data_c.data_a.data = 6
    d_2 = d_1
    std.io.printf("value d_2._data_a.data %d\n", d_2.data_a.data)
    std.io.printf("value d_2._data_c.data_a.data %d\n", d_2.data_c.data_a.data)
    return d_2.data_a.data + d_2.data_c.data_a.data
end
test.eq(testcopyassignment_D(), 5 + 2 + 6 + 2)

printtestheader("raii-compose.t - testing __copy construction for managed field")
terra testcopyconstruction_C()
    var c_1 : C
    c_1.data_a.data = 5
    var c_2 : C = c_1
    std.io.printf("value c_2._data_a.data %d\n", c_2.data_a.data)
    return c_2.data_a.data
end
test.eq(testcopyconstruction_C(), 5 + 2)

printtestheader("raii-compose.t - testing __copy construction for managed field and subfield")
terra testcopyconstruction_D()
    var d_1 : D
    d_1.data_a.data = 5
    d_1.data_c.data_a.data = 6
    var d_2 = d_1
    std.io.printf("value d_2._data_a.data %d\n", d_2.data_a.data)
    std.io.printf("value d_2._data_c.data_a.data %d\n", d_2.data_c.data_a.data)
    return d_2.data_a.data + d_2.data_c.data_a.data
end
test.eq(testcopyconstruction_D(), 5 + 2 + 6 + 2)
