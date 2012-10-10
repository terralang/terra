terra foo(a : &float)
	var b = a:as(&vector(float,4))
end
foo:compile()