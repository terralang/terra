struct Range {
    a : int;
    b : int;
}
Range.metamethods.__for = function(iter,body)
    return quote
        var it = iter
        for i = it.a,it.b do
            [ body(i) ]
        end
    end
end

terra foo()
    var v = Range { 0, 3 } 
    var vp = &v
    var i = 0
    for e in vp do i = i + e end
    return i
end
assert(3 == foo())