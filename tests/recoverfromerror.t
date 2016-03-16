


dostuff = macro(function()
	pcall(function()
	    terra what()
	        return " " / 1
        end
    end)
	return 4
end)

terra foobar()
	return dostuff()
end
assert(4 == foobar())