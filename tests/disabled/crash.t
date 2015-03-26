


terra bar(a : &int)
	@a = 4
	print("hi")
end
terra foo(a : &int)
	bar(a)
	print("hi")
end


bar:setinlined(false)
foo:setinlined(false)
foo(nil)