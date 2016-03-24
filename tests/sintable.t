local N = 32

local tbl = terralib.newlist()
for i = 1,N do
	tbl:insert(math.sin( 2 * math.pi * (i-1)/N))
end
local ctable = terralib.constant(`arrayof(float,[tbl]))

terra sintable(a : float) : float
	var idx = int(a / (2 * math.pi) * N) 
	return ctable[idx]
end

sintable:disas()

print(sintable(0))
print(sintable(math.pi/4))