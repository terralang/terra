if not require("fail") then return end
terra foo()
	var a : vector(&int,3)
end

foo:compile()
