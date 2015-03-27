if not require("fail") then return end
struct A {}
function A.metamethods.__getentries(self)
	return 0
end

terra foo()
	var a : A
end

foo()
