
IO = terralib.includec("stdio.h")
local Class = terralib.require("lib/javalike")

A = Class.define("A")
    :member("a",int)
    :type()
    
terra A:double() : int
    return self.a*2
end
    
B = Class.define("B",A)
    :member("b",int)
    :type()
    
terra B:combine(a : int) : int
    return self.b + self.a + a
end
    
C = Class.define("C",B)
    :member("c",double)
    :type()
    
terra C:combine(a : int) : int
    return self.c + self.a + self.b + a
end

terra C:double() : double
    return self.a * 4
end

terra doubleAnA(a : &A)
    return a:double()
end

terra combineAB(b : &B)
    return b:combine(3)
end

terra returnA(a : A)
    return a
end

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

local test = require("test")
test.eq(23,foobar())

local Doubles
= Class.defineinterface("Doubles")
  :method("double",{} -> int)
  :type()

local Adds
= Class.defineinterface("Adds")
  :method("add", int -> int)
  :type()

local D 
= Class.define("D")
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

Animal = Class.define("Animal")
         :member("data",int)
         :type()
terra Animal:speak() : {}
    IO.printf("... %d\n",self.data)
end

Dog = Class.define("Dog",Animal)
      :type()
terra Dog:speak() : {}
    IO.printf("woof! %d\n",self.data)
end

Cat = Class.define("Cat",Animal)
      :type()
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

local Add = Class.defineinterface("Add")
            :method("add",int->int)
            :type()

local Sub = Class.defineinterface("Sub")
            :method("sub",int->int)
            :type()

local P = Class.define("P")
          :member("data",int)
          :implements(Add)
          :type()

local C = Class.define("C",P)
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
timeadd(v,100000000)
local e = terralib.currenttimeinseconds()
print(e - b)
print(v.data)

local Add = Class.defineinterface("Add")
            :method("add",int->int)
            :type()


