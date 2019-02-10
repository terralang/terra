
local function CountedType(basetype)
    local struct CountedImpl {
        val: basetype
        count: int
    }
    return CountedImpl
end
CountedType = terralib.memoize(CountedType)

local function accessCounted(field)
    field.basename = field.field
    field.basetype = field.type
    field.type = CountedType(field.basetype)
    field.field = label(field.field)
    field.virtualEntries = {
        {
            field = field.basename .. "_count",
            type = int,
            accessor = function(obj) return `obj.[field.field].count end
        },
        {
            field = field.basename,
            type = field.basetype,
            accessor = function(obj)
                return quote
                    obj.[field.field].count = obj.[field.field].count + 1
                in
                    obj.[field.field].val
                end
            end
        }
    }

    if field.init then
        field.init = `[field.type] {count = 0, val = [field.init]}
    else
        field.init = `[field.type] {count = 0}
    end

end

local function initialized(value)
    return function(field)
        field.init = value
    end
end


local function SpecialEntries(class)
    class.virtualEntries = terralib.newlist()
    for _, v in ipairs(class.entries) do
        if v.virtualEntries then
            class.virtualEntries:insertall(v.virtualEntries)
        end
    end

    if #class.virtualEntries > 0 then
        local namemap = {}
        for _, v in ipairs(class.virtualEntries) do
            namemap[v.field] = v
        end
        class.metamethods.__entrymissing = function(obj, name)
            if namemap[name] then
                return namemap[name].accessor(obj)
            end
            return --error("No such field "..tostring(name).." in struct")
        end
    end

    terra class:init()
        [class.entries:filter(
            function(field) return field.init end
        ):map(
            function(field) return quote self.[field.field] = field.init end end
        )]
    end
end

local struct foo (SpecialEntries) {
    a (terralib.annotationcompose(initialized(1), accessCounted)): int
    b (initialized(2)): int
    c (accessCounted): int
}

terra pow(b: int, p: int): int
    if b == 1 then
        return 1
    end
    if p < 0 then
        return 0
    elseif p == 0 then
        return 1
    elseif p == 1 then
        return b
    else
        var part = pow(b, p/2)
        if (p and 1) == 1 then
            return part * part * b
        else
            return part * part
        end
    end
end

terra bar()
    var x: foo
    x:init()

    x.a = x.a + x.b * x.c

    return pow(2, x.a)*pow(3, x.a_count)*pow(5, x.b)*pow(7, x.c)*pow(11, x.c_count)
end

assert(bar() == 163350)
