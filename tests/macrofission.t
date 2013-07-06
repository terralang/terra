
checkm = macro(function(expN,expT,...)
	expN = expN:asvalue()
	expT = expT:asvalue()
	local exps = {...}
	assert(expN == #exps)
	local sum = 0
	for i,e in ipairs(exps) do
		sum = sum + #e:gettypes()
	end
	assert(expT,sum)
	return 1
end)
local two = {1,2}
local twoin1 = quote in 1,2 end
local four = {1,2,quote in 1,2 end}
local fourb = {1,2,quote in 1,[quote in 2 end] end }
local twowithstuff = {1,2,quote var a = 4 end}
terra foo()
	checkm(1,1,1)
	checkm(2,2,two)
	checkm(1,2,twoin1)
	checkm(2,1,(two))
	checkm(3,4,four)
	checkm(3,4,fourb)
	checkm(3,3,truncate(3,fourb))
	checkm(3,2,twowithstuff)
	checkm(3,3,1,two)
	checkm(2,3,1,twoin1)
	checkm(3,2,1,(two))
	checkm(4,5,1,four)
	checkm(4,5,1,fourb)
	checkm(4,4,1,truncate(3,fourb))
	checkm(4,3,1,twowithstuff)
end

foo()