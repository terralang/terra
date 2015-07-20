local destination = ...

local function exe(cmd,...)
    cmd = string.format(cmd,...)
    if os.execute(cmd) ~= 0 then
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
    local archivepath,objectfile = line:match("^(.*)%(([^(]*)%)$")
    local archivename = archivepath:match("/([^/]*)%.a$")
    if not exists( ("%s/%s/%s"):format(destination,archivename,objectfile) ) then
        exe("mkdir -p %s/%s",destination,archivename) 
        exe("cd %s/%s; ar x %s %s",destination,archivename,archivepath,objectfile)
    end
end