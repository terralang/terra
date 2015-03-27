if not require("fail") then return end

terra foo()
    var a = 8
    return a(8)
end
foo()
