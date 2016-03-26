J = require("lib/javalike")


Drawable = J.Interface("Drawable", { draw = {} -> {} })

struct Shape(J()) {
	foo : int
}


struct Square(J(Shape,Drawable)) {
	length : int 
}

terra Square:draw() : {}  end

Drawable:Define()

terra bar()
 var a : &Square = Square.alloc()
 a:draw()
end

bar()