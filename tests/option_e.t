local ffi = require("ffi")

local function getcommand()
    local prefix = terralib and terralib.terrahome and
                   terralib.terrahome .."/bin/terra" or "../terra"
    if ffi.os == "Windows" then
        prefix = prefix:gsub("[/\\]","\\\\")
    end
    return prefix
end

-- On windows, if the source exe has a space in it, we have to surround not only the paths with quotes, but also the entire command with quotes
local cmd = " -e \"local c = terralib.includec([[stdio.h]]); terra f() c.printf([[hello]]) end; f(); print()\""
if ffi.os == "Windows" then
  cmd = [[cmd /c ""]] .. getcommand() .. "\"" .. cmd .. "\""
else
  cmd = getcommand() .. cmd
end

print(cmd)
assert(os.execute(cmd) == 0)