

struct Range {
    a : int;
    b : int;
}
Range.metamethods.__for = function(iter,body)
    return quote
        var it = iter
        for i = it.a,it.b do
            [body(i)]
        end
    end
end

terra foo()
    var a = 0
    for i in Range {0,10} do
        a = a + i
    end
    return a
end

assert(foo() == 10*9/2)