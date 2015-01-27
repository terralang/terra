require("fail")

terra foo(a : int)
	return 1
end

terra foo(a : &int8)
	return 2
end

terra doit()
	foo(array(3))
end

print(doit())
