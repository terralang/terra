A = { foo = long }
terra foobar(a : A.foo, b : &int) : int
	::alabel::
	goto alabel
	var a,b : int = 1,2
	repeat until 1.1
	while 1 do
	end
	if true then 
	elseif false then
	end
	return 1
end
foobar()
foobar()
