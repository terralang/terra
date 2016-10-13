local util = require("terrautil")
local T = terralib.irtypes

T:Define [[
    TerraData = (Type type) unique
]]

function T.TerraData:init()
    function self.__tostring()
        return ("terradata<%s>"):format(tostring(self.type))
    end
end

-- equivalent to ffi.typeof, takes a cdata object and returns associated terra type object
function terra.typeof(obj)
    local mt = getmetatable(obj)
    if not T.TerraData:isclassof(mt) then
        error(("expected a terradata<T> type but found '%s'"):format(terra.type(obj)))
    end
    return mt.type
end

-- terra.stringraw is provided by tcompiler.cpp
function terra.string(ptr,len)
    local typ = terra.typeof(ptr)
    if type(len) ~= "number" then
        if terra.types.rawstring ~= typ then
            error(("expected a '%s' but found '%s'"):format(tostring(terra.types.rawstring),tostring(typ)))
        end
    else
        if not typ:ispointer() then
            error(("expected a pointer type but found '%s'"):format(tostring(typ)))
        end
    end
    return terra.stringraw(ptr,len)  
end

function terra.offsetof(terratype,field)
    if not T.struct:isclassof(terratype) then
        error(("expected a terra struct but found"):format(terra.type(terratype)))
    end
    terratype:complete()
    local layout = terratype:getlayout()
    local idx = layout.keytoindex[field] 
    if not idx then
        error(("no field '%s' in struct '%s'"):format(tostring(field),tostring(terratype)))
    end
    return terra.llvmoffsetof(terra.jitcompilationunit,terratype,idx)
end

function terra.new(terratype,...)
    error("NYI - new")
end
function terra.cast(terratype,obj)
    terratype:complete()
    error("NYI - cast")
end

--[[

### Rules for converting Terra values to Lua objects, adapted from LuaJIT FFI:

integers that can fit in a double  --> "number"
boolean -> "boolean"

everything becomes "terradata", which as a "userdata" with sizeof(T) whose payload
is the Terra value, the metatable is per-type and defines standard operations for that type in Lua

### 
]]


function T.terrafunction:__call(...)
    if not self.ffiwrapper then
        local terraffi = require("terraffi")
        self.ffiwrapper = terraffi.wrap(self) 
    end
    return self.ffiwrapper(...)
end