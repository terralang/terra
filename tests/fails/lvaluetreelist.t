if not require("fail") then return end



terra notlvalues()
	var a = 1
	a,a,[quote in a,4 end] = 5,6,7,8
end

notlvalues:compile()
