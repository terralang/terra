local function reporterr(depth,what,idx,expectedtypename,value)
    local fmt = "bad %s #%d to '%s' expected '%s' but found '%s'"
    local funcname = debug.getinfo(depth,"n").name or "?"
    local err = fmt:format(what,idx,funcname,expectedtypename,type(value))
    local mt = getmetatable(value)
    if mt then
        err = ("%s (metatable = %s)"):format(err,tostring(mt))
    end
    error(err,depth)
end

local function check(depth,typ,what,idx,value)
    local typekind = type(typ)
    if typekind == "string" then
        if type(value) ~= typ then
            reporterr(depth+1,what,idx,typ,value)
        end
        return value
    elseif typekind == "table" then
        local isclassof = typ.isclassof
        if isclassof then
            if not isclassof(typ,value) then
                reporterr(depth+1,what,idx,typ,value)
            end
            return value
        end
        -- fallthrough
    end
    local funcname = debug.getinfo(depth,"n").name
    error(("bad type annotation for %s #%d to '%s', expected string or table with :isclassof method but found '%s'")
        :format(what,idx,funcname,typekind),depth ) 
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