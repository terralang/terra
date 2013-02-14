
IO = terralib.includec("stdio.h")
local Class = terralib.require("lib/javalike2")

struct A {
  a : int
}
terra A:times2() : int
    return self.a*2
end
   
struct B {
  b : int
} 
Class.extends(B,A)
    
terra B:combine(a : int) : int
    return self.b + self.a + a
end
    

struct C {
  c : double
}
Class.extends(C,B)

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

terra foobar()

    var a = A.alloc()
    a.a = 1
    var b = B.alloc()
    b.a,b.b = 1,2

    var c = C.alloc()
    c.a,c.b,c.c = 1,2,3.5

    var r = doubleAnA(a) + doubleAnA(b) + doubleAnA(c) + combineAB(b) + combineAB(c)

    a:free()
    b:free()
    c:free()

    return r
end

assert(23 == foobar())

--[[
local test = require("test")
test.eq(23,foobar())

local Doubles
= Class.interface()
  :method("double",{} -> int)
  :type()

local Adds
= Class.interface()
  :method("add", int -> int)
  :type()

local D 
= Class.class()
  :member("data",int)
  :implements(Doubles)
  :implements(Adds)
  :type()

terra D:double() : int
    return self.data * 2
end

terra D:add(a : int) : int
    return self.data + a
end


terra aDoubles(a : &Doubles)
    return a:double()
end

terra aAdds(a : &Adds)
    return a:add(3)
end

terra foobar2()
    var a : D
    a:init()
    a.data = 3
    return aDoubles(&a) + aAdds(&a)
end

test.eq(12,foobar2())

]]
local IO = terralib.includec("stdio.h")
struct Animal {
  data : int
}
terra Animal:speak() : {}
    IO.printf("... %d\n",self.data)
end

struct Dog {
}
Class.extends(Dog,Animal)
terra Dog:speak() : {}
    IO.printf("woof! %d\n",self.data)
end

struct Cat {
}

Class.extends(Cat,Animal)

terra Cat:speak() : {}
    IO.printf("meow! %d\n",self.data)
end

terra dospeak(a : &Animal)
    a:speak()
end

terra barnyard()
    var c : Cat
    var d : Dog
    c:init()
    d:init()
    c.data,d.data = 0,1

    dospeak(&c)
    dospeak(&d)
end
barnyard()

--[[
local Add = Class.interface()
            :method("add",int->int)
            :type()

local Sub = Class.interface()
            :method("sub",int->int)
            :type()

local P = Class.class()
          :member("data",int)
          :implements(Add)
          :type()

local C = Class.class()
          :extends(P)
          :member("data2",int)
          :implements(Sub)
          :type()

terra P:add(b : int) : int
   self.data = self.data + b
   return self.data
end

terra C:sub(b : int) : int
    return self.data2 - b
end

terra doadd(a : &Add)
    return a:add(1)
end

terra dopstuff(p : &P)
    return p:add(2) + doadd(p) 
end

terra dosubstuff(s : &Sub)
    return s:sub(1)
end



terra dotests()
    var p : P
    p:init()
    var c : C
    c:init()
    p.data = 1
    c.data = 1
    c.data2 = 2
    return dopstuff(&p) + dopstuff(&c) + dosubstuff(&c)
end

test.eq(dotests(),15)


terra timeadd(a :&P, N : int)
  IO.printf("%p\n",a)
  for i = 0, N,10 do
    a:add(1)
    a:add(1)
    a:add(1)
    a:add(1)
    a:add(1)
    a:add(1)
    a:add(1)
    a:add(1)
    a:add(1)
    a:add(1)
  end
  return a
end


var a : C

terra doinit() : &P
  a:init()
  a.data = 0
  return &a
end

local v = doinit()
timeadd:compile()

local b = terralib.currenttimeinseconds()
--timeadd(v,100000000)
local e = terralib.currenttimeinseconds()
print(e - b)
print(v.data)
]]
