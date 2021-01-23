ffi = require "ffi"
if ffi.os == "Windows" then
  string=terralib.includec("string.h")
else
  string = terralib.includecstring [[
#include <string.h>

#if (_POSIX_C_SOURCE >= 200112L || _XOPEN_SOURCE >= 600) && ! _GNU_SOURCE
int strerror_r_(int errnum, char *buf, size_t buflen) {
#else
char *strerror_r_(int errnum, char *buf, size_t buflen) {
#endif
  return strerror_r(errnum, buf, buflen);
}
]]
end

buf=terralib.new(int8[1024])
if ffi.os == "Windows" then
  string.strerror_s(buf,1024,1)
else
  string.strerror_r_(1,buf,1024)
end
print(ffi.string(buf))
