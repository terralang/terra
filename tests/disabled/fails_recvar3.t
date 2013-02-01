var a = bar()
terra bar()
	return foo()
end
terra foo() : int
	return a
end
foo()