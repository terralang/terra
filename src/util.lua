local util = {}


--returns a function string -> string that makes names unique by appending numbers
function util.uniquenameset(sep)
    local cache = {}
    local function get(name)
        local count = cache[name]
        if not count then
            cache[name] = 1
            return name
        end
        local rename = name .. sep .. tostring(count)
        cache[name] = count + 1
        return get(rename) -- the string name<sep><count> might itself be a type name already
    end
    return get
end

function util.isluajit()
    return type(rawget(_G,"jit")) == "table"
end

terra.isverbose = 0 --set by C api
function util.dbprint(level,...) 
    if terra.isverbose >= level then
        print(...)
    end
end
function util.dbprintraw(level,obj)
    if terra.isverbose >= level then
        terra.printraw(obj)
    end
end

function util.mkstring(self,begin,sep,finish)
    return begin..table.concat(self:map(tostring),sep)..finish
end

return util