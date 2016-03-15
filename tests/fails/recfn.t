if not require("fail") then return end
local terra foo() : {}
	bar()
end 
nop = 1
local
terra bar() : {}
	foo()
end


foo:printpretty()
