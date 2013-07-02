
terra foo()
	return 8.0,9
end

local torturechain = quote
	var a = 3.0
in
	[quote
		var b = 4
	 in
	 	[quote 
	 		var c = 5.0
	 	in
	 		a,b,c, [quote 
	 					var d = 6
	 				in
	 					[quote
	 						var e = 7.0
	 					in
	 						d,e,foo()
	 					end]
	 				end]
	 	end]
	 end]
end

terra bindit()
	var a,b,c,d,e,f,g = torturechain
	return a + b + c + d + e + f + g
end

local sum = 3+4+5+6+7+8+9 
assert(sum == bindit())

terra foo(z : int, a : int, b : int, c : int, d : int, e : int, f : int, g : int)
	return z + a + b + c + d + e + f + g
end


terra overloadit(a : int, b : int, c : int, d : int, e : int, f : int)
	return 0
end

terra overloadit(a : double, b : int, c : int, d : int, e : int, f : int)
	return 1
end


terra callit()
	return foo(0,torturechain)
end

terra callol()
	return overloadit(truncate(6,torturechain))
end

assert(callit() == sum)
assert(callol() == 1)

terra uselvalue()
	(torturechain) = 5
	return 1
end

terra usemultiplelvalues()
	truncate(4,torturechain) = 1,2,3,4
	return 1
end

assert(uselvalue() == 1)
assert(usemultiplelvalues() == 1)