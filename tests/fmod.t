local fmodf = terralib.externfunction("fmodf",{float,float} -> float)
local terra boom (m : float) : float
    return fmodf(m,3.14) --m % 3.14159
end

print(boom(0))