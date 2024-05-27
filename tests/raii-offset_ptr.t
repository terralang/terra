require "terralibext"   --load 'terralibext' to enable raii
local test = require("test")

local std = {
    io = terralib.includec("stdio.h")
}

struct offset_ptr{
    offset : int
    init : bool
}

offset_ptr.methods.__copy = terra(from : &int64, to : &offset_ptr)
    to.offset = [&int8](from) - [&int8](to)
    to.init = true
    std.io.printf("offset_ptr: __copy &int -> &offset_ptr\n")
end

local struct A{
    integer_1 : int64
    integer_2 : int64
    ptr : offset_ptr
}

terra test0()
    var a : A
    a.ptr = &a.integer_1
    var save_1 = a.ptr.offset
    std.io.printf("value of a.ptr.offset: %d\n", a.ptr.offset)
    a.ptr = &a.integer_2
    var save_2 = a.ptr.offset
    std.io.printf("value of a.ptr.offset: %d\n", a.ptr.offset)
    return save_1, save_2
end

--test the offset in bytes between ptr and the integers in struct A
test.meq({-16, -8},test0())