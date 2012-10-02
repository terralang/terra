local C = terralib.includecstring [[
	#include <objc/objc.h>
	#include <objc/message.h>
	#include <stdio.h>
]]
local struct ID {
	dummy : &uint8	
}
local OC = {}
setmetatable(OC, {
	 __index = function(self,idx)
	 	return `C.objc_getClass(idx):as(&ID)
	end
})
setmetatable(ID.methods,{
	defaulttable = getmetatable(ID.methods);
	__index = function(self,idx)
		local df = getmetatable(self).defaulttable[idx]
		if df then
			return df
		end
		return macro(function(ctx,tree,obj,...)
			local args = {...}
			local idx = idx:gsub("_",":")
			if #args >= 1 then
				idx = idx .. ":"
			end
			return `C.objc_msgSend((&obj):as(C.id),C.sel_registerName(idx),args):as(&ID)
		end)
	end
})
return OC
