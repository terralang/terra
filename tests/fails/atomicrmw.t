if not require("fail") then return end


terra foo()
	var a =  3
	return terralib.atomicrmw(&a,4)
end

foo()
