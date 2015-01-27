require("fail")
local function aa() end

terra foo()
  return aa.a
end
foo()
