local terraffi = {}
local List = terralib.newlist

-- HACK: terra.cast is not implemented yet, but the compiler
-- uses it to convert Lua numbers into Terra values
-- we need lua numbers in the wrapper to address the Lua stack
local literals = { `1, `2, `3, `4, `5, `6, `7, `8, `9, `10 }

local function classifytype(type)
    if "primitive" == type.kind then
        if type.type == "float" or type.type == "integer" and type.size < 8 then
            return "number"
        elseif type.type == "logical" then
            return "boolean"
        else -- number does not fit into Lua, it has to be userdata
            return "userdata"
        end
    else
        return "userdata"
    end
end

local struct lua_State
luaL_checknumber = terralib.externfunction("luaL_checknumber",{&lua_State,int} -> double)
lua_pushboolean = terralib.externfunction("lua_pushboolean",{&lua_State,bool} -> {})

local function getfromlua(type,L,position_)
    local position = literals[position_]
    local class = classifytype(type)
    if "number" == class then
        return `[type](luaL_checknumber(L,position))
    elseif "boolean" == class then
        return `lua_toboolean(L,position)
    elseif "userdata" == class then
        local msg = ("expected a userdata at position %d"):format(position_)
        return quote
            var result = lua_touserdata(L,position)
            if result == nil then
                lua_pushstring(L,msg)
                lua_error(L)
            end
        in @[&type](result)
        end
    else 
        error("unknown class - "..tostring(class))
    end
end

local function pushvaluetolua(type,L,value)
    local class = classifytype(type)
    if "number" == class then
        return `lua_pushnumber(L,value)
    elseif "boolean" == class then
        return `lua_pushboolean(L,value)
    elseif "userdata" == class then
        return quote 
            var result = [&type](lua_newuserdata(L,sizeof(type)))
            @result = type
        end
    end
end


function terraffi.wrap(terrafunction)
    local syms,exprs = List(),List()
    local fntype = terrafunction:gettype()
    return terra(L : &lua_State)
        escape
            local exprs = List()
            for i,a in ipairs(fntype.parameters) do
                exprs:insert(getfromlua(a,L,i))
            end
            emit quote
                var result = terrafunction(exprs)
                [ pushvaluetolua(fntype.returntype, L, result) ]
            end
        end
        return 1 -- TODO: handle unit as a special case (?)
    end
end

return terraffi