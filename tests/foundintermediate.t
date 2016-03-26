terra bar()
    escape
        local terra what() return foo(3) end
    end
    return 3
end
terra foo(a : int) : int
    return bar() + 1 + a
end

assert(3 + 1 + 2 == foo(2))