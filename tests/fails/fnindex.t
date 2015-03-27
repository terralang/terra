if not require("fail") then return end


terra foo()
end

terra bar()
    return foo + 1
end

bar()
