local destination = ...

local function exe(cmd,...)
    cmd = string.format(cmd,...)
    local res = { os.execute(cmd) }
    if type(res[1]) == 'number' and res[1] ~= 0 or not res[1] then
        print('Error during '..cmd..':', table.unpack(res))
        error("command failed: "..cmd)
    end
end
local function exists(path)
    local f = io.open(path)
    if not f then return false end
    f:close() 
    return true
end
for line in io.lines() do
    line = line:gsub("[()]"," ")
    local archivepath,objectfile = line:match("(%S+)%s+(%S+)")
    local archivename = archivepath:match("/([^/]*)%.a$")
    if not exists( ("%s/%s/%s"):format(destination,archivename,objectfile) ) then
        exe("mkdir -p %s/%s",destination,archivename) 
        exe("cd %s/%s; ar x %s %s",destination,archivename,archivepath,objectfile)
    end
end 