if not require("fail") then return end

terra foo()
    return nil + "a"
end
foo()
