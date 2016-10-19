local terraffi = {}
local util = require("terrautil")
local List = terralib.newlist
local T = terralib.irtypes
-- HACK: terra.cast is not implemented yet, but the compiler
-- uses it to convert Lua numbers into Terra values
-- we need lua numbers in the wrapper to address the Lua stack
local literals = { `1, `2, `3, `4, `5, `6, `7, `8, `9, `10 }

local function classifytype(type)
    if "primitive" == type.kind then
        if type.type == "float" or type.type == "integer" and type.bytes < 8 then
            return "number"
        elseif type.type == "logical" then
            return "boolean"
        else -- number does not fit into Lua, it has to be userdata
            return "terradata"
        end
    else
        return "terradata"
    end
end

local struct lua_State
luaL_checknumber = terralib.externfunction("luaL_checknumber",{&lua_State,int} -> double)
lua_pushboolean = terralib.externfunction("lua_pushboolean",{&lua_State,bool} -> {})
lua_pushvalue = terralib.externfunction("lua_pushvalue",{&lua_State,int} -> {})
lua_pushnumber = terralib.externfunction("lua_pushnumber",{&lua_State,double} -> {})
lua_toboolean = terralib.externfunction("lua_toboolean",{&lua_State,int} -> int)
lua_newuserdata = terralib.externfunction("lua_newuserdata",{&lua_State,int} -> &opaque)
lua_touserdata = terralib.externfunction("lua_touserdata",{&lua_State,int} -> &opaque)
lua_getmetatable = terralib.externfunction("lua_getmetatable",{&lua_State,int} -> int)
lua_setmetatable = terralib.externfunction("lua_setmetatable",{&lua_State,int} -> {})
lua_rawequal = terralib.externfunction("lua_rawequal",{&lua_State,int,int} -> int)
luaL_typerror = terralib.externfunction("luaL_typerror",{&lua_State,int,rawstring} -> {})
lua_settop = terralib.externfunction("lua_settop",{&lua_State,int} -> {})
terra lua_pop(L : &lua_State, n : int)
    lua_settop(L,-(n)-1)
end

terra checknumber(L : &lua_State, i : int) : double
    return luaL_checknumber(L,i)
end
terra checkboolean(L : &lua_State, i : int) : bool
    return lua_toboolean(L,i) ~= 0
end
terra checkterradata(L : &lua_State, ud : int, class : int, name : rawstring) : &opaque
    var p = lua_touserdata(L,ud)
    if p ~= nil then
        if lua_getmetatable(L,ud) ~= 0 then
            if lua_rawequal(L,-1,class) ~= 0 then
                lua_pop(L,1)
                return p
            end
        end
    end
    luaL_typerror(L,ud,name)
    return nil
end
terra newterradata(L : &lua_State, sz : int, class : int) : &opaque
    var result = lua_newuserdata(L,sz)
    lua_pushvalue(L,class)
    lua_setmetatable(L,-2)
    return result
end


local LUA_GLOBALSINDEX = `(-10002)
local function upvalueindex(i)
    i = assert(literals[i])
    return `LUA_GLOBALSINDEX - i
end

function terraffi.wrap(terrafunction)
    local exprs = List()
    local fntype = terrafunction:gettype()
    local upvalues = List()
    local upvalueindex_map = {}
    local function createupvalue(obj)
        if not upvalueindex_map[obj] then
             upvalues:insert(obj)
             upvalueindex_map[obj] = upvalueindex(#upvalues)
        end
        return upvalueindex_map[obj]
    end
    
    local function checktype(type,L,position_)
        local position = literals[position_]
        local class = classifytype(type)
   
        if "number" == class then
            return `[type](checknumber(L,position))
        elseif "boolean" == class then
            return `checkboolean(L,position)
        elseif "terradata" == class then
            local typename = tostring(type)
            local offset = createupvalue(T.TerraData(type))
            return `@[&type](checkterradata(L,position,offset,typename))
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
        elseif "terradata" == class then
            local offset = createupvalue(T.TerraData(type))
            return quote 
                var result = [&type](newterradata(L,sizeof(type),offset))
                @result = value
            end
        end
    end
    
    local terra wrapper(L : &lua_State)
        escape
            local exprs = List()
            for i,a in ipairs(fntype.parameters) do
                exprs:insert(checktype(a,L,i))
            end
            if terralib.types.unit == fntype.returntype then
                emit quote
                    terrafunction(exprs)
                    return 0
                end
            else
                emit quote
                    var result = terrafunction(exprs)
                    [ pushvaluetolua(fntype.returntype, L, result) ]
                    return 1
                end
            end
        end
    end
    wrapper:setname(terrafunction:getname().."_luawrapper")
    return terralib.bindtoluaapi(wrapper:compile(),unpack(upvalues))
end

local ffi_setvalue = terralib.externfunction("ffi_setvalue", {&lua_State,int,int,&opaque} -> {})
local ffi_pushcdata = terralib.externfunction("ffi_pushcdata", {&lua_State,int} -> &opaque)

local function wrapctype(fntypep)
    local ffi = require('ffi')
    local fntype = fntypep.type
    local syms,exprs = List(),List()
    local upvalues = List { }
    local upvalueindex_map = {}
    local function createupvalue(type)
        if not upvalueindex_map[type] then
             local obj = ffi.typeof(type:cstring())
             upvalues:insert(obj)
             upvalueindex_map[type] = `LUA_GLOBALSINDEX - [#upvalues + 1] -- + 1 because the first upvalue is the function pointer
        end
        return upvalueindex_map[type]
    end
    
    local function checktype(type,L,position)
        local idx = createupvalue(type)
        return quote
            var r : type
            ffi_setvalue(L,position,idx,&r)
        in r end
    end
        
    local function pushvaluetolua(type,L,value)
        local class = classifytype(type)
        if "number" == class then
            return `lua_pushnumber(L,value)
        elseif "boolean" == class then
            return `lua_pushboolean(L,value)
        elseif "terradata" == class then
            local idx = createupvalue(type)
            return quote 
                var result = [&type](ffi_pushcdata(L,idx))
                @result = value
            end
        end
    end
    
    local terra wrapper(L : &lua_State)
        escape
            local terrafunction = `[fntypep](lua_touserdata(L,LUA_GLOBALSINDEX - 1))
            local exprs = List()
            for i,a in ipairs(fntype.parameters) do
                exprs:insert(checktype(a,L,i))
            end
            if terralib.types.unit == fntype.returntype then
                emit quote
                    terrafunction(exprs)
                    return 0
                end
            else
                emit quote
                    var result = terrafunction(exprs)
                    [ pushvaluetolua(fntype.returntype, L, result) ]
                    return 1
                end
            end
        end
    end
    return { func = wrapper, upvalues = upvalues }
end
wrapctype = util.memoize(wrapctype)

function terraffi.wrapcdata(fntypep,fnptr)
    local launcher = wrapctype(fntypep)
    return terralib.bindtoluaapi(launcher.func:compile(),fnptr,unpack(launcher.upvalues))
end

return terraffi