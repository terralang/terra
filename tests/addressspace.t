-- Tests of pointers with address spaces.

-- The exact meaning of this depends on the target, but at least basic
-- code compilation should work.

local function ptr1(ty)
  -- A pointer in address space 1.
  return terralib.types.pointer(ty, 1)
end

terra test(x : &int, y : ptr1(int))
  -- Should be able to do math on pointers with non-zero address spaces:
  var a = [ptr1(int8)](y)
  var b = a + 8
  var c  = [ptr1(int)](b)
  var d = c - y
  y = c

  -- Casts should work:
  y = [ptr1(int)](x)
  x = [&int](y)

  return d
end
test:compile()
print(test)
