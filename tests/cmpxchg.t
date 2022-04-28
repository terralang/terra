terra cmpxchg_arm(x : &int, y : int, z : int)
  return terralib.cmpxchg(x, y, z, { success_ordering = "acq_rel", failure_ordering = "monotonic" })
end
cmpxchg_arm:printpretty(false)
cmpxchg_arm:disas()

local c = terralib.includecstring [[
#ifndef _WIN32
#include "stdlib.h"
#else
#include "malloc.h"
#include "errno.h"

int posix_memalign(void **p, size_t a, size_t s) {
  *p = _aligned_malloc(s, a);
  return *p ? 0 : errno;
}
#endif
]]

terra test_cmpxchg()
  var i : &int
  if c.posix_memalign([&&opaque](&i), 16, terralib.sizeof(int)) ~= 0 then
    return 0
  end

  @i = 1
  var r1 = cmpxchg_arm(i, 20, 300)
  -- Should be failure and value should be 1.
  if r1._0 ~= 1 then
    return 1
  end
  if r1._1 ~= false then
    return 2
  end

  var r2 = cmpxchg_arm(i, 1, 123)
  -- Should be success and value should be 1.
  if r2._0 ~= 1 then
    return 3
  end
  if r2._1 ~= true then
    return 4
  end

  var r3 = cmpxchg_arm(i, 123, 456)
  -- Should be success and value should be 123.
  if r3._0 ~= 123 then
    return 4
  end
  if r3._1 ~= true then
    return 5
  end

  return 6
end
print(test_cmpxchg())
assert(test_cmpxchg() == 6)
