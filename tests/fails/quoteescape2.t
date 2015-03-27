if not require("fail") then return end


q = nil
foo = macro(function(a)
	q = a
	return `0
end)


terra bar()
	var b : int
	do
		var a = 8
		b = foo(a)
	end
	return q + foo(b)
end

terra baz()
	return q
end

bar:printpretty()
print(bar())
