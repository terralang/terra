if not require("fail") then return end
terra d(a : int)
end
d:setinlined(false)

terra foo()
    ::what2::
    if true then
        defer d(1)
        ::what::
    end
    if true then
        goto what
    end
end
foo:compile()
