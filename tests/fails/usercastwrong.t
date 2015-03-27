if not require("fail") then return end


struct A {
	a : int
}

function A.metamethods.__cast(from,to,exp)
	return "a" 
end

terra foobar()
	var b : int = A { 3 }
	return b
end 

foobar()
