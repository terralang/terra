


terra foo()
	return 1,2,3,4
end


terra bar()
	var a,b,c = truncate(3,1,foo())
	return a + b + c
end

assert(bar() == 4)