local function createluawrapper(luafn)
    local typecache = {}
    return macro(function(...)
        local args = terralib.newlist {...}
        local argtypes = args:map("gettype")
        local fntype = argtypes -> {}
        if not typecache[fntype] then
            print("new",fntype)
            typecache[fntype] = terralib.cast(fntype,luafn)
        end
        local fn = typecache[fntype]
        return `fn([args])
    end)
end

local tprint = createluawrapper(print)
terra test()
    tprint(1,2,3.5)
    tprint(1)
    tprint(2)
end

test()