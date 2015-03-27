if not require("fail") then return end

struct A {
}

terra foo()
	var a : A
	a:bar()
end

foo()
