if not require("fail") then return end
terra bar()
    escape
        local terra what() return foo(3) end
    end
    return 3
end
terra foo(a : int)
    return 1 + a
end
