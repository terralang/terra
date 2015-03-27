if not require("fail") then return end
terra foo()
    var a : tuple(int)
    return a._1
end
foo()
