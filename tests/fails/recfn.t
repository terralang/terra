if not require("fail") then return end
local terra foo() : {}
	bar()
end local
terra bar() : {}
	foo()
end


foo:printpretty()
