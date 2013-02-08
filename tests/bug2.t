ffi = require("ffi")
cstdio = terralib.includec("stdio.h")

local vec4 = &vector(float,4)

local align = terralib.aligned 
terra lol( w : &float, out : &float)
  var a  = align(@vec4(w),4)
  align(vec4(out)[0], 4) = a
end

dat = ffi.new("float[?]",32)
for i=0,31 do dat[i]=i end
datO = ffi.new("float[?]",32)

lol:compile()
lol:printpretty()

lol(dat, datO)

