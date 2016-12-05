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
function util.memoize(fn)
    local info = debug.getinfo(fn,'u')
    local nparams = not info.isvararg and info.nparams
    local cachekey = {}
    local values = {}
    local nilkey = {} --key to use in place of nil when a nil value is seen
    return function(...)
        local key = cachekey
        for i = 1,nparams or select('#',...) do
            local e = select(i,...)
            if e == nil then e = nilkey end
            local n = key[e]
            if not n then
                n = {}; key[e] = n
            end
            key = n
        end
        local v = values[key]
        if not v then
            v = fn(...); values[key] = v
        end
        return v
    end
end

local weakkeys = { __mode = "k" }
function util.newweakkeytable()
    return setmetatable({},weakkeys)
end

return util
