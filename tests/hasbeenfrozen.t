struct A {
	a : int;
	b : int;
	c : &B
}
struct B {
	a : &A
}

local a = global(A)

terra foo :: {} -> int
function A.metamethods.__staticinitialize(self)
	print("A")
	assert(A:iscomplete())
	a:get().a = 4
end

function B.metamethods.__staticinitialize(self)
	print("B")
	assert(B:iscomplete())
	a:get().b = 3
	a:get().a = a:get().a + 1
end

terra foo()
	var b : B
	return a.a + a.b
end

assert(foo() == 8)