

struct A {
	a : int
}

terra A:__unm()
	return A { -self.a }
end

terra A:__sub(rhs : &A)
	return A { self.a - rhs.a }
end


terra doit()
	var a,b = A { 1 } ,  A { 2 }
	return (-(a - b)).a
end

assert(doit() == 1)
