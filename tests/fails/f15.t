if not require("fail") then return end

terra bar(a : int) return a end
terra foo()
    var a : &int = 7
    var d = bar(a)
end
foo()
