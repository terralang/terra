if not require("fail") then return end

terra foo(a : int)
	return terralib.select(vector(true,false), vector(3,4,5),-1)[0]
end

print(foo(1),foo(-1))
