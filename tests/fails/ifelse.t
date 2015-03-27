if not require("fail") then return end

terra foo(a : int)
	return terralib.select(a > 0, vector(1,1),"a")
end

print(foo(1),foo(-1))
