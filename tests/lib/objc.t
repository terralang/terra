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

local struct Wrapper {
    data : &C.objc_object
}
Wrapper.metamethods.__methodmissing = macro(function(sel,obj,...)
	local arguments = {...}
	sel = mangleSelector(sel,#arguments)
	return `Wrapper { C.objc_msgSend(obj.data,C.sel_registerName(sel),arguments) }
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
	 	return `Wrapper { C.id(C.objc_getClass(idx)) }
	end
})
OC.ID = Wrapper

return OC
