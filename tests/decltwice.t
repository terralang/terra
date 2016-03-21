
terra mything :: int -> int

terra mybar()
	return mything(4)
end

terra mything(a : int)
	return a
end

do end -- cause an ordering problem

terra mything :: int -> int

terra mybar2()
	return mything(4)
end


terra mything(a : int) return a + 1 end

assert(mybar() + 1 == mybar2())