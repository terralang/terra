
terra foo(a : double)
    var v0 : vector(double,3) = a
    var v1 : vector(int,3) = 4
    var v2 = v0 / v1
    var v3 = (v0 <= v1) or (v1 >= v0)
    var ptr = (&v2):as(&double)
    return v3[0] or v3[1] or v3[2]
    --return ptr[0] + ptr[1] + ptr[2]
end

print(foo(3))