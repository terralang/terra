local outputfilename = arg[1]

local ffi = require("ffi")
local findcmd = ffi.os == "Windows" and "cmd /c dir /b /s \"%s\"" or "find %q"

local listoffiles = {}
for i = 2,#arg,2 do
    local path,pattern = arg[i],arg[i+1]
    local p = assert(io.popen(findcmd:format(path)))
    print(findcmd:format(path))
    for l in p:lines() do
        if l:match(pattern) then
            table.insert(listoffiles,{ name = l:sub(#path+1), path = l })
        end
    end
end

local ContentTemplate = [[
static const uint8_t headerfile_%d[] = { %s 0x0};
]]
local RegisterTemplate = [[
static const char * headerfile_names[] = { %s, 0};
static const uint8_t * headerfile_contents[] = { %s };
static int headerfile_sizes[] = { %s };
]]

local function FormatContent(id,data)
    local r = {}
    for i = 1,#data do
        if (i-1) % 16 == 0 then
            table.insert(r,"\n        ")
        end
        table.insert(r,("0x%x, "):format(data:byte(i)))
    end
    return ContentTemplate:format(id,table.concat(r))
end
local nextid = 0
local filecache = {}

local output = {}

local names = {}
local files = {}
local sizes = {}

local function EmitRegister(name,contents)
    if not filecache[contents] then
        local id = nextid
        nextid = nextid + 1
        filecache[contents] = id
        table.insert(output,FormatContent(id,contents))
    end
    table.insert(names,("\n%q"):format(name))
    table.insert(files,("\nheaderfile_%d"):format(filecache[contents]))
    table.insert(sizes,("\n%d"):format(#contents))
end

for i,entry in ipairs(listoffiles) do
    local file = io.open(entry.path)
    local contents = file:read("*all")
    file:close()
    EmitRegister(entry.name,contents)
end

table.insert(output,RegisterTemplate:format(table.concat(names,","),table.concat(files,","),table.concat(sizes,",")))

local outputfile = io.open(outputfilename,"w")
outputfile:write(table.concat(output))
outputfile:close()