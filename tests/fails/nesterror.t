if not require("fail") then return end


terra foobar()
	return (1):foo()
end

terra noerror()
	foobar()
	return (1):foo()
end


noerror()
