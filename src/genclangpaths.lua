--See Copyright Notice in ../LICENSE.txt
--usage: genclangpaths.lua output /path/to/clang  [addition args to parse]
local outputfile,clang = unpack(arg)
local handle = assert(io.popen(clang .. " -v src/dummy.c -o build/dummy.o 2>&1", "r"))
local theline
for s in handle:lines() do
    if s:find("-cc1") then
        theline = s
        break
    end
end
assert(theline)

local file = io.open(outputfile,"w")
local function emitStr(str)
    file:write(("\"%s\",\n"):format(str))
end
file:write("static const char * clang_paths[] = {\n")

--also parse command line arguments to this script
theline = theline .. " " .. table.concat(arg," ",3) .. " -"
local flagStr
local accumStr
for a in theline:gmatch("([^ ]+) ?") do -- Tokenize on whitespace
    -- If this is an option, stop recording args and emit what we have
    if a:find("^-") and accumStr then 
        accumStr = accumStr:gsub("\\\\", "/")
                           :match("^%s*(.*%S)%s*$")
                           :match("^\"?([^\"]+)\"?$")
        if not accumStr:match("lib/clang") then -- do not include clang resource directory, which is handled at runtime
            emitStr(flagStr)
            emitStr(accumStr)
        end
        accumStr = nil
    end
    -- If this is an include option, emit the option and start recording args
    if a == "-I" or a:find("isystem$") then
        flagStr = a
        accumStr = ""
    -- If we are recording args, continue recording args
    elseif accumStr then 
        accumStr = accumStr .. a .. " "
    end
end

file:write("NULL\n};\n")
file:close()