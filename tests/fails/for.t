if not require("fail") then return end

terra foo(a : uint64, s : uint64)
    var r = 0
    for i = 0.0,a,s do
        r = r + i
    end
    return r
end



local test = require("test")
test.eq(foo(10,1),45)
test.eq(foo(10,2),20)
