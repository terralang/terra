

local op = setmetatable({},{ __index = function(self,idx) 
    return idx
end })
C = terralib.includec("stdio.h")
local function emit(buf,bufsiz,...)
    local str = ""
    local operands = {}
    for i = 1,select("#",...) do
        local v = select(i,...)
        local cv,e = v:asvalue()
        str = str .. (e and "%d" or tostring(cv)) .. " "
        if e then table.insert(operands,v) end
    end
    str = str.."\n"
    return `C.snprintf(buf,bufsiz,str,operands)
end
emit = macro(emit)

local c = "as28"
terra what(buf : rawstring, bufsiz : uint64)
    var b = 3
    emit(buf,bufsiz,1,3,4,3+3,op.what,b + 3)
end

local buf = terralib.new(int8[128])
what(buf,128)
local ffi = require("ffi")
local s = ffi.string(buf)
assert("1 3 4 6 what 6 \n" == s)
