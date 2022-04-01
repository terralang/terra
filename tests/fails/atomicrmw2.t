if not require("fail") then return end


terra foo()
	var a = 3
	return terralib.atomicrmw("add", &a, 4, {})
end

foo()
