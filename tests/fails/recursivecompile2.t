if not require("fail") then return end


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
