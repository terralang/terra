if not require("fail") then return end

terra foo()
    var a  : struct { a : int, b : int } = { a = 1, b = 2, c = 3}
    return a.a
end
foo()
