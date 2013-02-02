

local S = terralib.types.newstruct("mystruct")

struct A {
	v : int
}

S:addentry("what",A)

terra foo()
	var v : S
	return v.what.v
end

foo:compile()
