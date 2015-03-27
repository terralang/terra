if not require("fail") then return end

terra foo()
    var a  : struct { a : int, b : int } = {b = 1, a = 1,3}
    return a.a
end
foo()
