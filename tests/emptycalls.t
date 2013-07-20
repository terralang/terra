terra f(x : struct {})
	return x
end


print(f({}))

terra f2(x : struct {})
	return x,x
end

print(f2({}))

terra f3(x : struct{}, a : int)
	return a + 1
end

assert(f3({},3) == 4)

terra f4(x : struct {})
	return x,4
end

a,b = f4({})
assert(b == 4)

terra f5()
	return f({})
end

f5()