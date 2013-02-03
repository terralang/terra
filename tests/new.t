local c = terralib.includec("stdlib.h")

new = macro(function(ctx,tree,typquote)
    local typ = typquote:astype(ctx)
    return `[&typ](c.malloc(sizeof(typ)))
end)

local typ = int
terra doit()
    var a : &int = new(int)
    return a
end

doit()