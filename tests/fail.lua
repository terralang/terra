-- add require("fail") at the beginning of a file
-- makes sure the remainder of the file produces an error
package.loaded["fail"] = true
function failit(fn)
	local success,msg = xpcall(fn,debug.traceback)
	if success then
		error("failed to fail.",2)
	elseif not (msg:match "Errors reported during" or msg:match "Error occured while") then
		error("failed wrong: "..msg,2)
	end
	print(msg)
end
local srcfile = debug.getinfo(3).source:sub(2)
failit(assert(terralib.loadfile(srcfile)))
return false