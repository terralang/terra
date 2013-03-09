local f = assert(io.popen("uname", 'r'))
local s = assert(f:read('*a'))
f:close()

if s~="Darwin\n" then
  print("Warning, not running test b/c this isn't a mac")
else

local A = terralib.require("lib.objc")
local B = terralib.require("lib.objc")

assert(A == B)

end