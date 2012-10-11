ffi = require("ffi")
cstdio = terralib.includec("stdio.h")

local vec4 = &vector(float,4)

terra lol( w : &float, out : &float)
  var a  = attribute(@(w:as(vec4)), { align = 4 })
  attribute((out:as(vec4))[0], { align = 4 }) = a
end

dat = ffi.new("float[?]",32)
for i=0,31 do dat[i]=i end
datO = ffi.new("float[?]",32)

lol:compile()
lol:printpretty()

lol(dat, datO)

