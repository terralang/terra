local C = terralib.includecstring [[
	#include <objc/objc.h>
	#include <objc/message.h>
	#include <stdio.h>
]]
local OC = {}
setmetatable(OC, {
	 __index = function(self,idx)
	 	return `C.id(C.objc_getClass(idx))
	end
})
OC.ID = &C.objc_object
C.objc_object.metamethods.__methodmissing = macro(function(ctx,tree,idx,obj,...)
	local idx = idx:gsub("_",":")
	local args = {...}
	if #args >= 1 then
		idx = idx .. ":"
	end
	return `C.objc_msgSend(&obj,C.sel_registerName(idx),args)
end)

return OC
