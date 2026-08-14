-- An aggregate rvalue has to be the value its expression had when it was
-- evaluated. Copying an aggregate is compiled into a memcpy from the source
-- address, and that memcpy used to be left at the point where the copy is
-- consumed rather than the point where the value was read, so anything that
-- wrote to the source in between was picked up by the copy. Parallel assignment
-- is the case that was reported (see parallelassign.t and
-- https://github.com/terralang/terra/issues/500); the same rewrite is used for
-- passing aggregates to functions, which has the same problem.
--
-- Terra emits operands left to right, so an argument that reads a variable does
-- not see a later argument's writes to it. That order is what the compiler does
-- rather than something the manual promises, so these tests pin the
-- implementation; what is not negotiable is that each argument gets the value
-- its own expression produced.

struct vec { x : int, y : int }
struct big { d : double[16] }  -- 128 bytes: passed in memory, not registers

terra bump(p : &vec) : int
  p.x = 99
  return 0
end

terra bumpbig(p : &big) : int
  p.d[0] = 99
  return 0
end

terra bumparray(p : &int[64]) : int
  (@p)[0] = 99
  return 0
end

terra poke(p : &vec, v : int) : int
  p.x = v
  return 0
end

terra takevec(v : vec, ignored : int) : int
  return v.x
end

terra takebig(v : big, ignored : int) : int
  return int(v.d[0])
end

terra takearray(v : int[64], ignored : int) : int
  return v[0]
end

terra structarg()
  var a = vec {1, 2}
  return takevec(a, bump(&a)) * 100 + a.x
end
assert(structarg() == 199)

terra bigstructarg()
  var a : big
  a.d[0] = 1
  return takebig(a, bumpbig(&a)) * 100 + int(a.d[0])
end
assert(bigstructarg() == 199)

terra bigarrayarg()
  var a : int[64]
  a[0] = 1
  return takearray(a, bumparray(&a)) * 100 + a[0]
end
assert(bigarrayarg() == 199)

-- Through a pointer, which is what real code looks like.
terra throughpointer(a : &vec)
  return takevec(@a, bump(a))
end
terra runthroughpointer()
  var a = vec {1, 2}
  return throughpointer(&a) * 100 + a.x
end
assert(runthroughpointer() == 199)

-- The receiver of a method call is an aggregate too.
vec.methods.getx = terra(self : vec, ignored : int) : int
  return self.x
end
terra methodreceiver()
  var a = vec {1, 2}
  return a:getx(bump(&a)) * 100 + a.x
end
assert(methodreceiver() == 199)

-- Several aggregates in flight at once: every one of them has to be the value
-- read at its own position.
terra takethree(u : vec, i : int, v : vec, j : int, w : vec) : int
  return u.x * 10000 + v.x * 100 + w.x
end
terra severalargs()
  var a = vec {1, 2}
  return takethree(a, bump(&a), a, poke(&a, 7), a)
end
assert(severalargs() == 19907)

-- Aggregates that nothing writes to still take the plain single copy; this is
-- here so that the ordinary case keeps being exercised.
terra takepair(u : vec, v : vec) : int
  return u.x * 100 + v.x
end
terra plainargs()
  var a = vec {1, 2}
  var b = vec {10, 20}
  return takepair(b, a)
end
assert(plainargs() == 1001)

-- Constructors store the aggregate value straight into the tuple instead of
-- going through the memcpy rewrite, so these two never miscompiled. They are
-- here so that path stays covered if the rewrite is ever extended to it.
terra tuplevalue()
  var a = vec {1, 2}
  var t = { a, bump(&a) }
  return t._0.x * 100 + a.x
end
assert(tuplevalue() == 199)

terra returnpair() : {vec, int, int}
  var a = vec {1, 2}
  return a, bump(&a), a.x
end
terra returnedvalue()
  var r = returnpair()
  return r._0.x * 100 + r._2
end
assert(returnedvalue() == 199)

-- A deferred call reads its arguments where the defer statement is, not where
-- the block ends: that is what Terra already did for scalars, and aggregates
-- used to disagree because the copy was left behind at the end of the block.
local acc = global(int, 0)
terra observe(v : vec) : int
  acc = acc + v.x
  return 0
end
terra observescalar(n : int) : int
  acc = acc + n
  return 0
end
terra deferredaggregate()
  acc = 0
  var a = vec {1, 2}
  do
    defer observe(a)
    a.x = 99
  end
  return acc
end
terra deferredscalar()
  acc = 0
  var n = 1
  do
    defer observescalar(n)
    n = 99
  end
  return acc
end
assert(deferredaggregate() == 1)
assert(deferredaggregate() == deferredscalar())

-- The right hand side of an assignment is read before the left hand side's
-- address is computed, so a side effect in the address does not reach it.
terra lhssideeffect()
  var dst : vec[2]
  var a = vec {1, 2}
  dst[bump(&a)] = a
  return dst[0].x * 100 + a.x
end
assert(lhssideeffect() == 199)

-- Initializers behave the same way as assignments.
terra initializer()
  var a = vec {1, 2}
  var copy, ignored = a, bump(&a)
  return copy.x * 100 + a.x
end
assert(initializer() == 199)
