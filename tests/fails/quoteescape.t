if not require("fail") then return end


q = nil

foo = macro(function(a)
	q = a
	return `0
end)


terra bar()
	var a = 8
	return foo(a)
end

terra baz()
	return q
end

print(bar())
print(baz())
