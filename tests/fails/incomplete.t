require("fail")
struct A

terra foo2(a : &A)
	return a.b
end

foo2:compile()
