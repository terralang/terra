local outputfile = arg[1]
local file = io.open(outputfile,"w")

file:write("static const char * clang_paths[] = {\n")

local function endswith(string,suffix)
	return suffix == "" or string.sub(string,-string.len(suffix)) == suffix
end
local function emitStr(str)
	--TODO: this doesn't handled quotes in the string...
	file:write(("\"%s\",\n"):format(str))
end

local function isincludearg(a)
	return    (a:sub(1,1) == "-" and endswith(a,"isystem"))
	       or (a == "-I")
end

for i,a in ipairs(arg) do
	if isincludearg(a) and i+1 <= #arg and arg[i+1]:sub(1,1) == "/" then
		emitStr(a)
		emitStr(arg[i+1])
	end
end

file:write("NULL\n};\n")
file:close()