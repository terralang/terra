
struct Range {}
Range.metamethods.__for = function(a,b,c)
    return 1,2,3
end

terra foo()
    for i in Range {} do
    end
end

foo()