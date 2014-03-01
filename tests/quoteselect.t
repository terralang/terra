
local a = {}

local c = terralib.includec("stdio.h")

-- b = `c.printf("hello\n")
b = `84

terra foo()
	return b
end

foo()