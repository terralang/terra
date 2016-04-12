

C = terralib.isconstant

assert(C`1)

assert(not C`1+1)
a = 4
c = terralib.constant(`4+6)
print(c)
assert(C`a)
assert(C(c))
w = terralib.constant("what")
assert(C`"what")
assert(C(w))
assert(not C(nil))
assert(not C(4))