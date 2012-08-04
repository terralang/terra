

terra foo(a : int)
end
terra foo(a : &int8)
end


terra doit()
	var a = foo
end

doit()