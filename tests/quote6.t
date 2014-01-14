function mymacro()
    return {`4,`5}
end
mymacro = macro(mymacro)

local exps = {`2,`3, `mymacro()}

terra doit()
    return exps
end
local test = require("test")
local a,b,c,d = doit()
test.eq(a,2)
test.eq(b,3)
test.eq(c,4)
test.eq(d,5)
