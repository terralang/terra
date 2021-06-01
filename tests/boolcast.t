terra f1(x : int64)
    return [bool](x)
end

terra f2(x : int64)
    return not [bool](x)
end

assert(not f1(0))
assert(f2(0))
for _, x in ipairs({-2,-1,1,2,3,4,16,256,65536,4294967296}) do
    assert(f1(x))
    assert(not f2(x))
end
