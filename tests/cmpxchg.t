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
  if not (r1._0 == 1 and r1._1 == false) then
    return false
  end

  var r2 = cmpxchg_arm(i, 1, 123)
  -- Should be success and value should be 1.
  if not (r1._0 == 1 and r1._1 == true) then
    return false
  end

  var r3 = cmpxchg_arm(i, 123, 456)
  -- Should be success and value should be 123.
  if not (r1._0 == 123 and r1._1 == true) then
    return false
  end

  return true
end
assert(test_cmpxchg())
