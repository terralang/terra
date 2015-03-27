if not require("fail") then return end

terra foo()
   var a : int
   return a.b + 4
end
foo()
