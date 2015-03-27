if not require("fail") then return end
local function aa() end

terra foo()
  return aa.a
end
foo()
