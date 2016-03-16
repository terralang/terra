C = terralib.includec("stdio.h")

local whilebreak = quote
    var i = 0
    while i < 7 do
        if i == 3 then
            break
        end
        i = i + 1
    end
    return i
end


local repeatbreak = quote
    var z = 0
    repeat
        z = z + 1
        if z == 2 then
            break
        end
    until z == 7
    return z
end


local forbreak = quote
    var z = 0
    for i = 1, 10 do
        z = z + 1
        if i == 4 then
            break
        end
    end
    return z
end

local function withbreak(thebreak,thevalue)
    local terra whileoutside()
        var i = 0
        while i < 10 do
            [ thebreak ]
            i = i + 1
        end
        return -1
    end
    assert(whileoutside() == thevalue)
    local terra foroutside()
        for i = 1,10 do
            [ thebreak ]
        end
        return -1
    end
    assert(foroutside() == thevalue)
    local terra repeatoutside()
        var i = 0
        repeat
            [ thebreak ]
            i = i + 1
        until i == 10
        return -1
    end
    assert(repeatoutside() == thevalue)
    local terra simple()
        [ thebreak ]
    end
    assert(simple() == thevalue)
end
withbreak(forbreak,4)
withbreak(whilebreak,3)
withbreak(repeatbreak,2)
    
    