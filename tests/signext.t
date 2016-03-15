

terra bar()
	var a : uint8 = 255
	var b = foo(a)
	return a == b
end
terra foo(a : uint8)
	return a
end

print(bar())