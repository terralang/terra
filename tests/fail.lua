-- add require("fail") at the beginning of a file
-- makes sure the remainder of the file produces an error
package.loaded["fail"] = true
function failit(fn)
	local success,msg = pcall(fn)
	if success then
		error("failed to fail.",2)
	elseif not string.match(msg,"Errors reported during") then
		error("failed wrong: "..msg,2)
	end
end
local srcfile = debug.getinfo(3).source:sub(2)
failit(assert(terralib.loadfile(srcfile)))
os.exit(0)