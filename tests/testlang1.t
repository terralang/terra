#!../terra -l lib/testlang.t

print("hello")
local a = image "astring"
image 4
image and,or,&
image image
image akeyword
image foobar
print(a)
image bar 3
print(bar,bar1)

local image what 4 3
print(what)
print(foolist { a, b})
--test eos token
image