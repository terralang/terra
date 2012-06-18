
local c = terralib.includec("stdio.h")

terra foo()
    var a = "whatwhat\n"
    return c.puts(a)
end

local test = require("test")
test.eq(foo(),10)