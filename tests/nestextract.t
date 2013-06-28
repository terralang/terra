

struct A {
	a : int
}

count = global(int,0)

terra twoAs(a : int)
	return A {a}, A { a }
end

function A.metamethods.__cast(fromt,tot,exp)
	if tot == A and fromt == int then
		return `twoAs(exp)
	end
	error("what")
end

terra twoInts()
	count = count + 1
	return count,2
end

terra takesAnA(a : A)
	return a.a
end

dotwice = macro(function(exp)
	return {exp,exp}
end)

terra doit()
	return dotwice(takesAnA((twoInts()))) 
end


doit:printpretty()

local a,b = doit()

print(a,b)
assert(1 == a)
assert(2 == b)
