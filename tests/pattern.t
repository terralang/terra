
terra foobar()
    return 1,2
end

terra what()
    var _,a,b = 1,foobar()
    a,b = foobar()
    return a + b
end
terra what2()
    var a = foobar()
    var b,c = unpackstruct(a)
    return b+c
end

assert(what() == 3)
assert(what2() == 3)