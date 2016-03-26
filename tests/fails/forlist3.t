if not require("fail") then return end

struct Range {}
Range.metamethods.__for = function(iter,body)
    return body
end

terra foo()
    for i in Range {} do
    end
end

foo()
