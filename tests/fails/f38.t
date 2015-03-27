if not require("fail") then return end

terra foo()
    var a : int[2]
  return a[3.3]
end
foo()
