local c = label("c")
struct A {
    b : int
}
A.entries:insert({c,int})
assert(8 == terralib.sizeof(A))
assert(0 == terralib.offsetof(A,"b"))
assert(4 == terralib.offsetof(A,c))

terra getptr(b : bool)
    var a = "hihihi"
    return a
end

terra getint()
    return 1ULL
end

terra useptr(a : rawstring)
    terralib.printf("s: %s\n",a)
end
terra useint(a : uint64)
    terralib.printf("the int %d\n",int(a))
end

local r = getptr(true)
print(r)
useptr(r)
useint(getint())

assert(terralib.typeof(r) == rawstring)
assert(terralib.string(r,3) == "hih")
assert(terralib.string(r) == "hihihi")
print("R",terralib.string(r,3))