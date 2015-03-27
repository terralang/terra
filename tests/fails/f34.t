if not require("fail") then return end
aa = 4
aa = nil
terra foo()
  return aa
end
foo()
