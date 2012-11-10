J = terralib.require("lib/javalike")

Shape = J.class():member("foo",int):type()

Drawable = J.interface( { draw = {} -> {} } ) 
Square = J.class()
:extends(Shape):implements(Drawable):member("length",int)
:type()
terra Square:draw() : {}  end

terra bar()
 var a : &Square = Square.alloc()
 a:draw()
end

bar()