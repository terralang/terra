if not require("fail") then return end


terra foo(a : int)
end
terra foo(a : &int8)
end


terra doit()
	var a = foo(3)
end

doit()
