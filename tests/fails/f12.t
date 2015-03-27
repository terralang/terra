if not require("fail") then return end

terra foo()
    var a = { a = 1, a = 2, c = 3}
    return a.a
end
foo()
