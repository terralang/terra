if not require("fail") then return end

terra foo()
    return niltype + "a"
end
foo()
