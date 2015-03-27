if not require("fail") then return end

terra foo()
    var a  : struct { a : int, b : int } = {1, a = 2}
    return a.a
end
foo()
