if not require("fail") then return end
terra d(a : int)
end
d:setinlined(false)

terra foo()
    if true then
        defer d(1)
        ::what::
    end
    defer d(3)
    if true then
        goto what
    end
end
foo:compile()
