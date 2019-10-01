C = terralib.includecstring[[inline int testfunc(int a, int b) { return a + b; }]]

terra foobar() : int
	var a : int = 5
  return C.testfunc(a, 9)
end
assert(foobar() == 14)

terralib.saveobj("inline_c.exe", {main = foobar})