if not require("fail") then return end


terra foo()
	var a : &opaque = nil
	return a + 1
end
foo()
