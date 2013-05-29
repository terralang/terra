--See Copyright Notice in ../LICENSE.txt


local outputfile = arg[1]
local file = io.open(outputfile,"w")

file:write("static const char * clang_paths[] = {\n")

local function lines(str)
	local t = {}
	local function helper(line) table.insert(t, line) return "" end
	helper((str:gsub("(.-)\r?\n", helper)))
	return t
end

local function startswith(string, prefix)
	return prefix == "" or string.sub(string, 0, string.len(prefix)) == prefix
end
local function endswith(string,suffix)
	return suffix == "" or string.sub(string,-string.len(suffix)) == suffix
end

local function trim1(s)
	return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local function emitStr(str)
	--TODO: this doesn't (?) handle quotes in the string...
	str = trim1(string.gsub(str, "\\\\", "/"))
	if string.sub(str, 1, 1) ~= "\"" then
		str = ("\"%s\""):format(str)
	end
	file:write(("%s,\n"):format(str))
end

local function split(str, sep)
	local sep, fields = sep or ":", {}
	local pattern = string.format("([^%s]+)", sep)
	string.gsub(str, pattern, function(c) fields[#fields+1] = c end)
	return fields
end

local clang = arg[2]
local handle = assert(io.popen(clang .. " -v dummy.c -o ../build/dummy.o 2>&1", "r"))
local str = assert(handle:read("*a"))
handle:close()

local strlines = lines(str)
local theline = ""
for i,s in ipairs(strlines) do
	if string.find(s, "-cc1") then
		theline = s
		break
	end
end

local toks = split(theline, " ")
local capturing = false
local accumStr = ""
for i=1,table.getn(toks) do
	local currStr = toks[i]
	if startswith(currStr, "-") and accumStr ~= "" then
		emitStr(accumStr)
		accumStr = ""
		capturing = false
	end
	if currStr == "-I" or endswith(currStr, "isystem") then
		emitStr(currStr)
		capturing = true
	elseif capturing then
		accumStr = accumStr .. currStr .. " "
	end
end

file:write("NULL\n};\n")
file:close()