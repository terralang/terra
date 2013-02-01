
C = terralib.includec("stdio.h")
local Class = terralib.require("lib/javalike")
local Prints = Class.interface()
                    :method("print", {} -> {})
                    :type()
local Leaf = Class.class()
                  :member("data",int)
                  :implements(Prints)
                  :type()

terra Leaf:print() : {} 
  C.printf("%d\n",self.data) 
end

local Node = Class.class()
                  :extends(Leaf)
                  :member("next",&Leaf)
                  :type()
                  
terra Node:print() : {} 
  C.printf("%d\n",self.data) 
  self.next:print()
end

terra test()
  var a,b = Leaf.alloc(), Node.alloc()
  a.data,b.data,b.next = 1,2,a
  var p : &Prints = b
  p:print()
end

test()