


terra bar(a : &int)
	@a = 4
	terralib.printf("hi\n")
end
terra foo(a : &int)
	bar(a)
	terralib.printf("hi\n")
end


bar:setinlined(false)
foo:setinlined(false)
foo(nil)