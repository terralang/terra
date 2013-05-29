string=terralib.includec("string.h")
buf=terralib.new(int8[1024])
ffi = require "ffi"
string.strerror_r(1,buf,1024)
print(ffi.string(buf))
