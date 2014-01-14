

terra foobar()
	return (1):foo()
end

terra noerror()
	foobar()
	return (1):foo()
end


noerror()
