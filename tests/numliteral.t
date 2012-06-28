var a,b,c,d,e = 3,3.0,3.f,3LL, 3ULL

local exp = { "int32", "double", "float", "int64", "uint64" }
local v = {a,b,c,d,e}

local test = require("test")
for i,e in ipairs(v) do
	test.eq(tostring(e:gettype()),exp[i]) 
end