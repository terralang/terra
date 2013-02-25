struct A {
	a : int;
	b : int;
}

function A.metamethods.__finalizelayout(self)
	print("ABOUT TO COMPILE")
	for i,e in ipairs(self.entries) do
		e.field = "foo"..e.field
	end
end

terra foo()
	var a : A
	a.fooa = 3
	a.foob = 4
	return a.fooa + a.foob
end


assert(foo() == 7)