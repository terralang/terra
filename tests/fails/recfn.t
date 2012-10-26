local terra foo() : {}
	bar()
end local
terra bar() : {}
	foo()
end


foo:printpretty()