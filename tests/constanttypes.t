local c = terralib.constant
local a,b = c(1ULL),c(uint64,1ULL),c(true),c

assert(c(true):gettype() == bool)
assert(c(false):gettype() == bool)
assert(c(bool,false):gettype() == bool)
assert(c(1):gettype() == int)
assert(c(1.5):gettype() == double)
assert(c("what"):gettype() == rawstring)
print(c("what"))

terra A() return 10 end
terra B() return 11 end
terra C() return 12 end

local farray = c(`array(A,B,C))

terra doit(e : int)
    return farray[e]() + farray[2]()
end

farray:setinitializer(`array(C,B,A))

assert(doit(0) == 22)
assert(doit(1) == 21)
assert(doit(2) == 20)
doit:disas()

local t = c(true)
local f = c(false)

local one = c(1)
local of = c(1.5)
local agg = c(terralib.new(int[3],{1,2,3}))
local str = c("a string")

terra testit()
    return one == 1 and 1.5 == of and agg[0] == 1 and agg[1] == 2 and agg[2] == 3 and "a string" == str
end
assert(testit())