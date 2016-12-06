a = &int
b = int[3]
c = vector(int,3)

assert(a:getelementtype() == int)
assert(b:getelementtype() == int)
assert(c:getelementtype() == int)
d = symbol(int)
assert(d:gettype() == int)
