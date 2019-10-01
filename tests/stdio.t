C = terralib.includecstring[[
#include <stdio.h>
inline int testfunc(int a, int b) { return a + b; }]]

terra foobar() : int
	var a : int = 5
  C.printf("C: %i\n", C.testfunc(a, 9))
  return C.testfunc(a, 9)
end
assert(foobar() == 14)

terralib.saveobj("stdio.exe", {main = foobar})