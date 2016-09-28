local util = require("util")
local T = terralib.irtypes
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

function T.terrafunction:__call(...)
    if not self.ffiwrapper then
        local terraffi = require("terraffi")
        local wrapped = terraffi.wrap(self)
        self.ffiwrapper = terralib.bindtoluaapi(wrapped:compile())
    end
    return self.ffiwrapper(...)
end