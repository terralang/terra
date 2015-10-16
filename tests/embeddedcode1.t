import "lib/embeddedcode"

local c = 3
local a = 4
local b = defexp(a) a + c
local d = b(10)
assert(d == 13)


local e = def(x)
    return x + c + a
end
local f = e(4)
assert(f == 11)

local g = deft(x : int) return x + c + a end
g:disas()
assert(g(4) == 11)

local h = deftexp(x : int) x + c + a
h:disas()
assert(h(5) == 12)
