

local terra terrafoo(a : &Bar)
    baz(a:foo())
end
local struct Bar {}
local terra baz(a : int)
end
terra Bar:foo() return 1 end
local a = 4

assert(a == 4)
terrafoo:disas()