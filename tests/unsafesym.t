
local mymacro = macro(function(a)
    print(a:gettype())
    return {}
end)



terra foo(a : int)
    mymacro(a)
end

foo:compile()