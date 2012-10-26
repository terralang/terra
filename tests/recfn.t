local terra foo() : {}
	bar()
end and 
terra bar() : {}
	foo()
end

bar = nil

foo:printpretty()