local c = terralib.includec("stdlib.h")

new = macro(function(ctx,typquote)
    local typ = typquote:astype(ctx)
    return `c.malloc(sizeof(typ)):as(&typ)
end)

local typ = int
terra doit()
    var a : &int = new(int)
    return a
end

doit()