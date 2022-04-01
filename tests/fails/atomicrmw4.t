if not require("fail") then return end


terra foo()
	var a = true
	return terralib.atomicrmw("add", &a, true, {ordering = "monotonic"})
end

foo()
