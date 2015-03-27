if not require("fail") then return end

terra foo(c : int)
    var a : int8 = int8(&c)
end
foo(1)
