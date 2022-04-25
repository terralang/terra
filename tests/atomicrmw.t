local has_syncscope = terralib.llvm_version >= 50
local has_align = terralib.llvm_version >= 110
local has_fadd = terralib.llvm_version >= 90

print("atomicrmw test settings: synscope " .. tostring(has_syncscope) .. ", align " .. tostring(has_align) .. ", fadd " .. tostring(has_fadd))



-- Basic cases: integers with ordering/syncscope/alignment

terra atomic_add(x : &int, y : int, z : int, w : int, u : int)
  terralib.atomicrmw("add", x, y, {ordering = "seq_cst"})
  terralib.atomicrmw("add", x, z, {ordering = "acq_rel"})
  terralib.fence({ordering = "release"})
  escape
    if has_syncscope and has_align then
      emit quote
        terralib.atomicrmw("add", x, w, {ordering = "monotonic", syncscope = "singlethread", align = 16})
      end
    elseif has_syncscope then
      emit quote
        terralib.atomicrmw("add", x, w, {ordering = "monotonic", syncscope = "singlethread"})
      end
    else
      emit quote
        terralib.atomicrmw("add", x, w, {ordering = "monotonic"})
      end
    end
  end
  terralib.fence({ordering = "acquire"})
  terralib.atomicrmw("add", x, u, {ordering = "monotonic", isvolatile = true})
end
atomic_add:printpretty(false)
atomic_add:disas()

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

terra add()
  var i : &int
  if c.posix_memalign([&&opaque](&i), 16, terralib.sizeof(int)) ~= 0 then
    return 0
  end

  @i = 1
  atomic_add(i, 20, 300, 4000, 50000)

  return @i
end

print(add())
assert(add() == 54321)



-- Returns previous value

terra atomic_add_and_return(x : &int, y : int)
  return terralib.atomicrmw("add", x, y, {ordering = "acq_rel"})
end
atomic_add_and_return:printpretty(false)
atomic_add_and_return:disas()

terra add_and_return()
  var i : int = 1

  var r = atomic_add_and_return(&i, 20)

  return r + i
end

print(add_and_return())
assert(add_and_return() == 22)



-- Floating point

if has_fadd then
  terra atomic_fadd(x : &double, y : double)
    terralib.atomicrmw("fadd", x, y, {ordering = "monotonic"})
  end
  atomic_fadd:printpretty(false)
  atomic_fadd:disas()

  terra fadd()
    var f : double = 1.0

    atomic_fadd(&f, 20.0)

    return f
  end

  print(fadd())
  assert(fadd() == 21.0)
end


-- Pointers

terra atomic_xchg_pointer(x : &&int, y : &int)
  return terralib.atomicrmw("xchg", x, y, {ordering = "acq_rel"})
end
atomic_add_and_return:printpretty(false)
atomic_add_and_return:disas()

terra xchg_pointer()
  var i : int = 1
  var j : int = 20
  var k = &i

  var r = atomic_xchg_pointer(&k, &j)

  return r == &i and k == &j
end

print(xchg_pointer())
assert(xchg_pointer())
