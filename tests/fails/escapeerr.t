if not require("fail") then return end


function bar()
	return foo + 1
end

struct A {
	a : foo + 1
}

struct B {
	a : bar()
}

terra foobar()
	var a : A
	var b : B
end

foobar:compile()
