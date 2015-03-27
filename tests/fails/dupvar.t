if not require("fail") then return end


terra foo()
	var a = 3
	var a = 4
	return a
end

print(foo())
