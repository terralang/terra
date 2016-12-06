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
function A:__staticinitialize()
	print("A")
	assert(A:iscomplete())
	a:get().a = 4
end

function B:__staticinitialize()
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
