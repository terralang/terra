struct A {}
function A.metamethods.__getentries(self)
	return 0
end

terra foo()
	var a : A
end

foo()
