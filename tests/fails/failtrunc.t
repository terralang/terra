if not require("fail") then return end

terra foo() : {}
	return (foo()),4
end
foo()
