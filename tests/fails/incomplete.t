if not require("fail") then return end
struct A

terra foo2(a : &A)
	return a.b
end

foo2:compile()
