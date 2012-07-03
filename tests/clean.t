local c = terralib.includec("stdio.h")

iamclean = macro(function(ctx,arg)
    return quote
        var a = 3
        return a,arg
    end
end)
    
terra doit()
    var a = 4
    iamclean(a)
end

local a,b = doit()
local test = require("test")
test.eq(a,3)
test.eq(b,4)