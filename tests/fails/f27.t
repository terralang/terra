if not require("fail") then return end

terra foo()
    return niltype(8)
end
foo()
