A = { foo = long }
anumber = { foo = 100 }
terra foobar(a : double, b : double) : double
	
	goto alabel
	var d = b + a
	::alabel::
	
end
foobar:compile()
--no fancy wrappers to call the function yet, so use luajit's ffi....
local ffi = require("ffi")
ffi.cdef("typedef struct { double (*fn)(double,double); } my_struct;") 
local func = ffi.cast("my_struct*",foobar.fptr)
print("EXECUTING FUNCTION:")
print(func.fn(1,4))

--[[
	::alabel::
	goto alabel
	var a,b = 1,2
	var e = -b
	var c : int = a + b
	var d = anumber.foo2
	-- @b = 1
	repeat until 1.1
	while 1 do
	end
	if true then 
	elseif false then
	end
	return 1
	var e =  1 + 3.3
	e = 1
	return 1
	var f = &e
	var g = @f
	e,f = 3,&e ]]