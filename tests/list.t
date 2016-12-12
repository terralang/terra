local List = require("terralist")


local a = List { 2,3,4 }


local b = a:map(function(x) return x + 1 end)
for i,v in ipairs(b) do
    assert(i+2 == v)
end
local c = b:mapi(function(i,x) return x - i end)
for i,v in ipairs(c) do
    assert(v == 2)
end

local s = 0
a:app(function(x) s = s + x end)
assert(s == 9)
a:appi(function(i,x) s = s + i + x end)
assert(s == 24,s)

local r = a:filteri(function(i,x) return (i+x) <= 5 end)
assert(#r == 2 and r[2] == 3)
local r = a:filter(function(x) return x % 2 == 0 end)
assert(#r == 2 and r[2] == 4)

local r = a:flatmapi(function(i,x) return List{x,x+i+1} end)
assert(#r == 2*#a and r[4] == 6)

local r = a:flatmapi(function(i,x) return List{x,x+1} end)
assert(#r == 2*#a and r[4] == 4)

assert(a:findi(function(i,x) return i == 2 and x == 3 end) == 3)
assert(a:findi(function() return false end) == nil)

assert(a:find(function(x) return x == 2 end) == 2)
assert(a:find(function(x) return false end) == nil)

local r = a:partitioni(function(i,x) return i % 2, x end)
assert(#r[0] == 1 and r[0][1] == 3 and #r[1] == 2,#r[1])
local r = a:partition(function(x) return x % 2, x end)
assert(#r[0] == 2 and r[0][1] == 2 and #r[1] == 1,#r[1])
assert(a:rev()[1] == 4 and a:rev()[3] == 2)

local v34 = a:sub(2)

assert(v34[1] == 3 and v34[2] == 4)

local v3 = a:sub(2,-2)
assert(v3[1] == 3 and #v3 == 1)

local v34 = a:sub(-2)
assert(v34[1] == 3 and v34[2] == 4)
assert(15 == a:foldi(0,function(i,s,x) return i+s+x end))
assert(9 == a:fold(0,"+"))
assert(24 == a:fold(1,"*"))

assert(9 == a:reducei(function(i,s,x) return s + x end))

local Wrap
local Wrapper = {}
function Wrapper:plus(rhs) return Wrap(self.a + rhs.a) end
function Wrap(x)
    setmetatable({ a = x }, {__index = Wrapper})
end

local A = { a = 3 }
local B = { a = 4 }
function A:plus(rhs,c) return self.a + rhs.a + c end
function B:plus(rhs,c) return self.a + rhs.a + c end

local l = List { A, B}
assert(7 + 4 == l:reduce("plus",4))

assert(a:existsi(function(i,x) return i == 2 and x == 3 end))
assert(a:exists(function(x) return x == 3 end))
assert(not a:exists(function(x) return x == -1 end))

assert(a:alli(function(i,x) return type(x) == "number" end))
assert(not a:alli(function(i,x) return x == 2 end))
assert(a:all(tonumber))
assert(not a:all("not"))
assert(not a:exists("not"))
assert(tostring(List{1,2}) == "{1,2}")
assert(List{}:reduceor(3,function()end) == 3)

assert(List{1,5}:reduceori(3,function(i,x,y) return x+y end) == 6)
