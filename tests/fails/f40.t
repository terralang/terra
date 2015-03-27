if not require("fail") then return end

terra foo()
  return  { [3] = 4 }
end
foo()
