

struct A {}

function A.metamethods.__getmethod()
	error("nope!")
end

terra foo()
	var a : A
	return a:bar()
end

foo()
