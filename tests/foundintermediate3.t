if not require("fail") then return end
terra bar()
    escape
        print(foo:gettype())
    end
    return 3
end
terra foo(a : int)
    return 1 + a
end
