

local a = "hi"

function failit(fn)
	local success,msg = xpcall(fn,debug.traceback)
	if success then
		error("failed to fail.",2)
	elseif not (msg:match "b : int = a") then
		error("failed wrong: "..msg,2)
	end
	print(msg)
end

failit(function()
terra foo()
   var b : int = a
end
end)
