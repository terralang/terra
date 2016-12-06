
struct A{}


--terra A:foo :: int -> int
local a = terra :: int -> int
terra foo()
    return a(3)
end

terra a(n : int)
    return n+1
end


assert(4 == foo())


terra A:foo :: int -> int

terra b()
    var s  : A
    return s:foo(3)
end

do end

terra A:foo(n : int)
    return n+2
end

assert(b() == 5)



terra A:foo :: int -> int

terra b()
    var s  : A
    return s:foo(3)
end


terra A:foo(n : int)
    return n+3
end

assert(b() == 6)
