

terra a(x : int) : int
    if x == 0 then
        b()
    end
    return 4
end

terra b() : int
    return a(3)
end

var global = a(1)

terra c() : int
    var v = a(1) + global
    if v == 0 then
        return d()
    end
    return v
end

terra d() : int
    c()
end

print(c())
