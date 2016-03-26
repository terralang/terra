local terra foo() : {}
	bar()
end
local terra bar() : {}
	foo()
end

bar = nil

foo:printpretty()