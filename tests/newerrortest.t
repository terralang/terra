print(xpcall(function()
local a = macro(function(a)
    error("no")
end)

terra what()
    a()
end
end,debug.traceback))