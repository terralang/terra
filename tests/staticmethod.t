struct A {
}
A.__getmethod = function(self,idx)
    return tonumber(string.sub(idx,2,-1))
end
terra foo()
    return [A:getmethod("f33")] + [A:getmethod("b34")]
end
assert(67 == foo())
