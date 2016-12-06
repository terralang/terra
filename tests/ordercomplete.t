

struct A {
	a : int
}

struct B {
	a : A
}

function A.__staticinitialize()
	print("STATIC INIT A")
	local terra what(b : B)
	end
end

function B.__staticinitialize()
	print("STATIC INIT B")
end

terra foo(b : B)
end

foo:compile()
