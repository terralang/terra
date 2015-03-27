if not require("fail") then return end
terra foo()
    defer 3
end
foo()
