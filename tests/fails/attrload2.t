require("fail")


terra foo()
	var a = 3
	return terralib.attrload(a,{})
end

foo()
