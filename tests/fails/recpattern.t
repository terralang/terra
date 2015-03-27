if not require("fail") then return end

foo = global(2)
terra a() : int
    b()
    c()
    return 1
end

terra b() : int
    a()
    return 2
end

terra c() : {}
    return start() + foo
end

terra start() : int
    a()
    return 1
end

start()
