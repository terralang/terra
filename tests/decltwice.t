
terra mything : int -> int

terra mybar()
	return mything(4)
end

terra mything(a : int)
	return a
end

terra mything : int -> int

terra mybar2()
	return mything(4)
end

assert(mybar() == mybar2())