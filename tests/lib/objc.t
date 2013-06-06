local ffi = require("ffi")
if ffi.os == "Windows" then
	return
end

local C = terralib.includecstring [[
	#include <objc/objc.h>
	#include <objc/message.h>
	#include <stdio.h>
]]
local mangleSelector


--replace methods such as:   myobj:methodcall(arg0,arg1)
--with calls to the objc runtime api: objc_msgSend(&obj,sel_registerName("methodcall"),arg0,arg1) 

C.objc_object.metamethods.__methodmissing = macro(function(sel,obj,...)
	local arguments = {...}
	sel = mangleSelector(sel,#arguments)
	return `C.objc_msgSend(&obj,C.sel_registerName(sel),arguments)
end)

function mangleSelector(sel,nargs)
	local sel = sel:gsub("_",":")
	if nargs >= 1 then
		sel = sel .. ":"
	end
	return sel
end

local OC = {}
setmetatable(OC, {
	 __index = function(self,idx)
	 	return `C.id(C.objc_getClass(idx))
	end
})
OC.ID = &C.objc_object

return OC
