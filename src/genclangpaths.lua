--See Copyright Notice in ../LICENSE.txt
--usage: genclangpaths.lua output /path/to/clang  [addition args to parse]
local ffi = require("ffi")
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
local accumStr
for a in theline:gmatch("([^ ]+) ?") do
	if a:find("^-") and accumStr then
		emitStr(accumStr:gsub("\\\\", "/")
		                :match("^%s*(.+%S)%s*$")
	                    :match("^\"?([^\"]+)\"?$"))
		accumStr = nil
	end
	if a == "-I" or a:find("isystem$") then
		emitStr(a)
	    accumStr = ""
	elseif accumStr then
		accumStr = accumStr .. a .. " "
	end
end

file:write("NULL\n};\n")
file:close()