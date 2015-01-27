require("fail")

terra bar() end

terra foo()
    return bar() + 3
end
foo()
