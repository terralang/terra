if not require("fail") then return end

terra foo()
   var a : struct {}
   return a.b + 4
end
foo()
