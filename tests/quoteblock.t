
local a = symbol(int)
local myquote = quote
	var [a] = 3
end

terra bar()
	[myquote];
	return [a]
end

print(bar())