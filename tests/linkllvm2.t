

terra add(a : int, b : int)
    return a + b
end

local r = terralib.saveobj(nil,"bitcode",{ add = add })
local addlib = terralib.linkllvmstring(r)
add2 = addlib:extern("add", {int,int} -> int)

assert(add2(3,4) == 7)