if not require("fail") then return end

struct Range {}
Range.metamethods.__for = function(a,b,c)
    return {1,3},2,3
end

terra foo()
    for i in Range {} do
    end
end

foo()
