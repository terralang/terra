
IO = terralib.includec("stdio.h")
local Class = require("lib/javalike")

struct A(Class()) {
  a : int;
  bb : &B
}
struct B(Class(A)) {
  b : int;
  aa : &A
} 


terra A:times2() : int
    return self.a*2
end
    
terra B:combine(a : int) : int
    return self.b + self.a + a
end
    

struct C(Class(B)) {
  c : double
}

terra C:combine(a : int) : int
    return self.c + self.a + self.b + a
end
terra C:times2() : double
    return self.a * 4
end

terra doubleAnA(a : &A)
    return a:times2()
end

terra combineAB(b : &B)
    return b:combine(3)
end

terra returnA(a : A)
    return a
end
terra foobar1()
  var c = C.alloc()
  c.a,c.b,c.c = 1,2,3.5
  return c:times2()
end

assert(foobar1() == 4)

