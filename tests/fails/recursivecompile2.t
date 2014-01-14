

terra bar() : {}
	foo()
end

terra baz()
	bar()
end
terra foo() : {}
	bar();
	[ baz
	  :compile() ]
end

print(foo())
