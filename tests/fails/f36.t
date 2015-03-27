if not require("fail") then return end
local aa = { b = 4}
terra foo()
  return aa.a
end
foo()
