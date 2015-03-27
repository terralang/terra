if not require("fail") then return end

terra bar() end

terra foo()
    return bar() + 3
end
foo()
