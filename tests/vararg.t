C = terralib.includecstring [[
#include <stdio.h>
#include <string.h>
#include <stdarg.h>

int checkargs(const char* f, va_list vl)
{
  if(strcmp(f, "%i%i%f%s"))
    return 1;
    
  if(va_arg(vl, int) != -10)
    return 2;
  if(va_arg(vl, unsigned long long) != 60000000000001ULL)
    return 3;
  if(va_arg(vl, double) != 60.01)
    return 4;
  if(strcmp(va_arg(vl, const char*), "TesT"))
    return 5;
  return 0;
}

]]

-- Test passthrough of varargs to another function

local va_start = terralib.intrinsic("llvm.va_start", {&int8} -> {})
local va_end = terralib.intrinsic("llvm.va_end", {&int8} -> {})

terra Log(prefix : rawstring, f : rawstring, ...) : int
  if C.strcmp(prefix, "preFIX") ~= 0 then
    return 8
  end
  
  var vl : C.va_list
  va_start([&int8](&vl))
  var i = C.checkargs(f, vl)
  if i ~= 0 then
    return i
  end
  va_end([&int8](&vl))
  return 0
end

terra invoke() : int
  Log("preFIX", "%i%i%f%s", -10, 60000000000001ULL, 60.01, "TesT")
end

assert(invoke() == 0)