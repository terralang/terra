

terra bar(a : int)
	return 4,5
end

terra foo()
	do
	end
	::what::
	goto what
	while 4 < 3 do
		return 3,4,bar(1)
	end
	var a = 0.0
	if a < 3 then
		a = -(a + 1)
	end

	if a < 3 then
		a = -a + 1
	elseif a > 4 then
		a = a - 1
	end
	repeat
		a = a + 1
	until a > 55
	var b,c = 4,5
	a,b = 5,c
	var d = array(1,2,3)
	b = (&a)[1]
	var e : int = a
	var g = terralib.select(true,0,1)
	return 3,4,bar(1)
end

foo:compile()
foo:printpretty()

