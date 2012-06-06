struct A { a : int }
struct B {a : int, b : A}

local C = struct { int }
local D = struct { double, C }

terra anon()
	var b : B
	b.a = 4
	b.b.a = 3
	
	var d : D
	d._0 = 1.0
	d._1._0 = 2
	
	b = d
	
	return b.a + b.b.a 
end

test = require("test")
test.eq(anon(),3)