
terra foo()
    return 1 + 1
end
foo()
local c = terralib.includec("mytest.h")

local test = require("test")
