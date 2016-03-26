if not require("fail") then return end

local a = {}
local b = a

terra a.mything :: int -> int

terra a.mybar()
	return mything(4)
end

terra a.mything(a : int)
	return a
end

--do end -- consider a duplicate definition error?

terra b.mything :: int -> int

terra b.mybar2()
	return mything(4)
end


terra b.mything(a : int) return a + 1 end

assert(mybar() + 1 == mybar2())