if not require("fail") then return end
terralib.fulltrace = true

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
