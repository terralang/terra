local util = require("util")
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
    error("NYI - typeof")
end
function terra.string(ptr,len)
    error("NYI - string")
end
function terra.new(terratype,...)
    error("NYI - new")
end
function terra.offsetof(terratype,field)
    terratype:complete()
    error("NYI - offsetof")
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