if not require("fail") then return end


terra foo()
	var a =  3
	terralib.attrstore(a,4,{})
end

foo()
