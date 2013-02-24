

struct A {
	a : int
}

function A.metamethods.__cast(_,_,from,to,exp)
	return true,"a" 
end

terra foobar()
	var b : int = A { 3 }
	return b
end 

foobar()
