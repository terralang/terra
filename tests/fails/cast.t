if not require("fail") then return end


terra foo()
	var b = 3
	var a = [double] b
end

foo:compile()
