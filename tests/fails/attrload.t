

terra foo()
	var a =  3
	return terralib.attrload(&a,4)
end

foo()