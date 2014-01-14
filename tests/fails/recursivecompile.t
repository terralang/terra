

terra bar() : {}
	foo()
end
terra foo() : {}
	bar();
	[ bar
	  :compile() ]
end

print(foo())
