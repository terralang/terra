if not require("fail") then return end
local a = {}
terra foo()
  return  a + 20
end
foo()
