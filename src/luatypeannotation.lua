local util = require("terrautil")
local List = require("terralist")

local function expectedtype(typeobj,value)
    local err = ("expected '%s' but found '%s'"):format(tostring(typeobj),type(value))
    local mt = getmetatable(value)
    if mt then
        err = ("%s (metatable = %s)"):format(err,tostring(mt))
    end
    return err
end

local function reporterr(depth,what,idx,msg)
    local fmt = "bad %s #%d to '%s' %s"
    local funcname = debug.getinfo(depth,"n").name or "?"
    local err = fmt:format(what,idx,funcname,msg)
    error(err,depth)
end

local function istype(typ,value)
    local typekind = type(typ)
    if typekind == "string" then
        if type(value) == typ then
            return true
        else
            return false, expectedtype(typ,value)
        end
    elseif typekind == "table" then
        local isclassof = typ.isclassof
        if isclassof then
            local valid, msg = isclassof(typ,value)
            if valid then
                return true
            else
                return false,msg or expectedtype(typ,value)
            end
        end
    end
    return false, ("because it has a bad type annotation, expected string or table with :isclassof method but found '%s'"):format(typekind)
end

local function check(depth,typ,what,idx,value)
    local valid,msg = istype(typ,value)
    if valid then
        return value
    end
    reporterr(depth+1,what,idx,msg)
end

function __argcheck(typ,idx,value)
    return check(2,typ,"argument",idx,value)
end

-- have to use recursion to handle nil values in ... correctly
local function doretcheck(N,types,i,v,...)
    if i > N then
        return
    end
    return check(2+i,types[i],"value being returned",i,v),doretcheck(N,types,i+1,...)
end

-- note: __retcheck is always a tailcall so debug info for the function actually returning
-- is not on the stack, instead we have to report errors relative to the function that
-- called it "value being returned #2 to 'caller_fn'" is supposed to convey that
function __retcheck(types,...)
    local expected = #types
    local actual = select("#",...)
    if actual > expected then
        error(("expected %d return values but found %d"):format(expected,actual),2)
    end
    return doretcheck(expected,types,1,...)
end

-- Type constructors for common checks
local ListOfType = {}
ListOfType.__index = ListOfType
function ListOfType:isclassof(value)
    if not List:isclassof(value) then
        return false, expectedtype(tostring(self),value)
    end
    if #value > 0 then
        local first = value[1]
        local valid,msg = istype(self.element,first)
        if not valid then
            return false, ("%s as first element of %s"):format(msg,tostring(self))
        end
    end
    return true
end
function ListOfType:__tostring()
    return ("ListOf(%s)"):format(tostring(self.element))
end
function ListOf(type)
    return setmetatable({ element = type },ListOfType)
end
ListOf = util.memoize(ListOf)

local OptionOfType = {}
OptionOfType.__index = OptionOfType
function OptionOfType:isclassof(value)
    if value == nil then
        return true
    end
    return istype(self.element,value)
end
function OptionOfType:__tostring()
    return ("OptionOf(%s)"):format(tostring(self.element))
end
function OptionOf(type)
    return setmetatable({ element = assert(type) },OptionOfType)
end
OptionOf = util.memoize(OptionOf)

local MapOfType = {}
MapOfType.__index = MapOfType
function MapOfType:isclassof(value)
    if type(value) ~= "table" then
        return false, expectedtype(tostring(self),value)
    end
    for k,v in pairs(value) do
        local valid, msg = istype(self.key,k)
        if not valid then
            return false, ("%s as key of %s"):format(msg,tostring(self))
        end
        local valid, msg = istype(self.value,v)
        if not valid then
            return false, ("%s as value of %s"):format(msg,tostring(self))
        end
        break -- only check one entry, all type annotations should be O(1) time
    end
    return true
end
function MapOfType:__tostring()
    return ("MapOf(%s,%s)"):format(tostring(self.key),tostring(self.value))
end
function MapOf(key,value)
    return setmetatable({ key = assert(key), value = assert(value) },MapOfType)
end
MapOf = util.memoize(MapOf)


