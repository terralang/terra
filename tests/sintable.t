local N = 32
local tbl = terralib.new(float[N])
for i = 1,N do
	tbl[i-1] = math.sin( 2 * math.pi * (i-1)/N)
end

local ctable = terralib.constant(tbl)

terra sintable(a : float) : float
	var idx = (a / (2 * math.pi) * N):as(int) 
	return ctable[idx]
end

sintable:disas()

print(sintable(0))
print(sintable(math.pi/4))