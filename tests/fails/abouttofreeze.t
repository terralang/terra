if not require("fail") then return end
struct A {
	a : int;
	b : int;
}

function A.metamethods.__finalizelayout(self)
	self:freeze()
end

terra foo()
	var a : A
	a.fooa = 3
	a.foob = 4
	return a.fooa + a.foob
end


assert(foo() == 7)
