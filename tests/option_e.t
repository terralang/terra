local ffi = require("ffi")

local function getcommand()
    local prefix = terralib and terralib.terrahome and
                   terralib.terrahome .."/bin/terra" or "../terra"
    if ffi.os == "Windows" then
        prefix = "cmd /c " .. prefix:gsub("[/\\]","\\\\")
    end
    return prefix
end

assert(os.execute(getcommand() .. " -e \"local c = terralib.includec([[stdio.h]]); terra f() c.printf([[hello]]) end; f(); print()\"") == 0)
