


local terra bar()
	return 1
end 
struct A {
	a : int
} 
local struct B {
	a : int
}
terra B:foo()
	return self.a
end 
terra foo()
	var b , a  = B{4}, A{5}
	return 1 + b:foo()
end
local terra mydecl :: {} -> {}
struct mystructdecl

print(bar())

print(foo())
