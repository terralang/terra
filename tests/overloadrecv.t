

struct A {
	a : int
}

A.methods.foo = terralib.overloadedfunction("foo")
A.methods.foo:adddefinition(terra(self :&A, a : int, b : uint8)
	return 1
end)
A.methods.foo:adddefinition(terra(self : &A, a : double, b : uint8)
	return 2
end)

terra useit()
	var a = A { 3 }
	var pa = &a
	return a:foo(1,1) + a:foo(1.1,1) + pa:foo(1,1) + pa:foo(1.1,1)
end

assert(6 == useit())