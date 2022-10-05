ffi = require "ffi"
if ffi.os == "Windows" then
  string=terralib.includec("string.h")
else
  string = terralib.includecstring [[
#include <string.h>

// Clang 15 seems to define _GNU_SOURCE now, so this check is not
// reliable. Not sure what the "proper" way is to do it is at this
// point. Work around it with checks for specific OSes.
#if (_POSIX_C_SOURCE >= 200112L || _XOPEN_SOURCE >= 600) && ! _GNU_SOURCE || defined(__APPLE__) || defined(__FreeBSD__)
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
