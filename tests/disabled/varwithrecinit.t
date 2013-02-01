var a = bar(7)

terra bar(x : int) : int
	if  x > 0 then
		return bar(x - 1)
	end
	return 0
end

terra usea()
	return a
end

usea()