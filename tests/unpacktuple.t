

terra foo()
 return 1,2
end

terra foo2()
 return {a = 1, b = 2}
end

assert(unpacktuple(1) == 1)
assert(unpacktuple(foo()) == 1)
assert(unpacktuple(foo2()).a == 1)