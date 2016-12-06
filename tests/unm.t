

struct A {
	a : int
}

A.__unm = terra(self : &A)
	return A { -self.a }
end

A.__sub = terra(self : &A, rhs  : &A)
	return A { self.a - rhs.a }
end

terra doit()
	var a,b = A { 1 } ,  A { 2 }
	return (-(a - b)).a
end

assert(doit() == 1)
