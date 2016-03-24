
C = terralib.includec("stdio.h")

local Class = require("lib/javalike")


local Prints = Class.Interface("Prints",{ print = {} -> {} })

struct Leaf(Class(nil,Prints)) {
  data : int
}
terra Leaf:print() : {} 
  C.printf("%d\n",self.data) 
end


struct Node(Class(Leaf)) {
  next : &Leaf
}

terra Node:print() : {} 
  C.printf("%d\n",self.data) 
  self.next:print()
end

Prints:Define()

terra test()
  var a,b = Leaf.alloc(), Node.alloc()
  a.data,b.data,b.next = 1,2,a
  var p : &Prints.type = b
  p:print()
end

test()