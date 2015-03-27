if not require("fail") then return end
bar = macro(function() return 2 end)
terra foo()
    defer bar()
end
foo()
