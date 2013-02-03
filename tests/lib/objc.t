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
setmetatable(C.objc_object.methods,{
	defaulttable = getmetatable(C.objc_object.methods);
	__index = function(self,idx)
		if string.sub(idx,1,2) == "__" then --ignore metamethods
			return nil
		end
		return macro(function(ctx,tree,obj,...)
			local args = {...}
			local idx = idx:gsub("_",":")
			if #args >= 1 then
				idx = idx .. ":"
			end
			return `C.objc_msgSend(&obj,C.sel_registerName(idx),args)
		end)
	end
})

return OC
