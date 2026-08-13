-- Parallel assignment evaluates every right hand side before it updates any of
-- the left hand sides, so `a, b = b, a` is a swap no matter what a and b are.
-- Aggregates used to break that: copying one was compiled into a memcpy that
-- read the source at the point of the store rather than the point of the read,
-- so an assignment earlier in the same statement was visible to a later one.
-- https://github.com/terralang/terra/issues/500

struct vec { x : int }
struct pair { u : vec, v : vec }
struct nested { p : pair, tag : int }
struct big { d : double[16] }  -- 128 bytes; structs take the memcpy path at any size

-- Scalars, which always worked, as a baseline for everything below.
terra scalars()
  var a, b = 1, 10
  a, b = b, a
  return a * 100 + b
end
assert(scalars() == 1001)

terra structlocals()
  var a, b = vec {1}, vec {10}
  a, b = b, a
  return a.x * 100 + b.x
end
assert(structlocals() == 1001)

terra structfields()
  var p = pair { vec {1}, vec {10} }
  p.u, p.v = p.v, p.u
  return p.u.x * 100 + p.v.x
end
assert(structfields() == 1001)

terra throughpointer()
  var p = pair { vec {1}, vec {10} }
  var q = &p
  q.u, q.v = q.v, q.u
  return p.u.x * 100 + p.v.x
end
assert(throughpointer() == 1001)

terra throughderef()
  var a, b = vec {1}, vec {10}
  var pa, pb = &a, &b
  @pa, @pb = @pb, @pa
  return a.x * 100 + b.x
end
assert(throughderef() == 1001)

terra wholestructs() : {int, int, int, int}
  var a = pair { vec {1}, vec {2} }
  var b = pair { vec {10}, vec {20} }
  a, b = b, a
  return a.u.x, a.v.x, b.u.x, b.v.x
end
local r = wholestructs()
assert(r._0 == 10 and r._1 == 20 and r._2 == 1 and r._3 == 2)

terra nestedstructs() : {int, int, int, int}
  var a = nested { pair { vec {1}, vec {2} }, 3 }
  var b = nested { pair { vec {10}, vec {20} }, 30 }
  a, b = b, a
  return a.p.u.x, a.tag, b.p.u.x, b.tag
end
r = nestedstructs()
assert(r._0 == 10 and r._1 == 30 and r._2 == 1 and r._3 == 3)

terra bigstructs()
  var a : big
  var b : big
  a.d[0], b.d[0] = 1, 10
  a, b = b, a
  return int(a.d[0]) * 100 + int(b.d[0])
end
assert(bigstructs() == 1001)

-- Arrays are the one case with a size threshold: only those at least
-- MEM_ARRAY_THRESHOLD (64) bytes are copied with a memcpy, so test both sides.
terra smallarrays()
  var a : int[2]
  var b : int[2]
  a[0], b[0] = 1, 10
  a, b = b, a
  return a[0] * 100 + b[0]
end
assert(smallarrays() == 1001)

terra bigarrays()
  var a : int[64]
  var b : int[64]
  a[0], b[0] = 1, 10
  a, b = b, a
  return a[0] * 100 + b[0]
end
assert(bigarrays() == 1001)

-- The idiom this shows up in most often: swapping two elements of an array.
terra swapelements(i : int, j : int)
  var a : vec[4]
  for k = 0, 4 do
    a[k] = vec {k}
  end
  a[i], a[j] = a[j], a[i]
  return a[0].x * 1000 + a[1].x * 100 + a[2].x * 10 + a[3].x
end
assert(swapelements(0, 3) == 3120)
assert(swapelements(1, 2) == 213)

terra rotate()
  var a, b, c = vec {1}, vec {2}, vec {3}
  a, b, c = c, a, b
  return a.x * 100 + b.x * 10 + c.x
end
assert(rotate() == 312)

-- Only some of the values on either side are aggregates.
terra mixed()
  var a, b = vec {1}, vec {10}
  var n = 7
  a, n, b = b, a.x, a
  return a.x * 1000 + n * 100 + b.x
end
assert(mixed() == 10101)

-- A right hand side that a *later* right hand side clobbers through a call, so
-- the copy has to have been taken before the call ran.
terra clobber(v : &vec) : int
  v.x = 99
  return 0
end
terra acrosscall()
  var a, b = vec {1}, vec {10}
  var n : int
  a, n, b = b, clobber(&b), a
  return a.x * 100 + b.x
end
assert(acrosscall() == 1001)

-- The shape from the bug report: an operator overload on the first right hand
-- side, a plain read of the just-assigned field on the second.
struct v2 { x : double, y : double }
v2.metamethods.__add = terra(a : v2, b : v2) : v2
  return v2 { a.x + b.x, a.y + b.y }
end
v2.metamethods.__sub = terra(a : v2, b : v2) : v2
  return v2 { a.x - b.x, a.y - b.y }
end
v2.metamethods.__mul = terra(a : v2, s : double) : v2
  return v2 { a.x * s, a.y * s }
end

struct particle { pos : v2, vel : v2 }

terra integrate(part : &particle, drag : double)
  part.pos, part.vel = part.pos + part.vel * (1 - drag), part.pos
end

-- The same step written the other way round, which the bug report observed to
-- work by luck: nothing reads a field that was already written.
terra integrateflipped(part : &particle, drag : double)
  part.vel, part.pos = part.pos, part.pos + part.vel * (1 - drag)
end

-- And the same step with an explicit temporary, which never miscompiled.
terra integrateref(part : &particle, drag : double)
  var oldpos = part.pos
  part.pos = part.pos + part.vel * (1 - drag)
  part.vel = oldpos
end

local function run(step)
  local terra go() : {double, double, double, double}
    var part = particle { v2 {1, 2}, v2 {10, 20} }
    step(&part, 0.5)
    -- Recover the velocity the way the bug report did, from the change in
    -- position: a zero here is the miscompilation.
    var vel = part.pos - part.vel
    return part.pos.x, part.pos.y, vel.x, vel.y
  end
  return go()
end

for _, step in ipairs({integrate, integrateflipped, integrateref}) do
  local r = run(step)
  assert(r._0 == 6 and r._1 == 12)
  assert(r._2 == 5 and r._3 == 10)
end

-- Assigning something to itself has to survive being turned into a copy whose
-- source and destination are the same address.
terra selfassign()
  var a = big {}
  a.d[0] = 7
  a = a
  var b = a
  b.d[0] = 8
  a, b = a, b
  return int(a.d[0]) * 100 + int(b.d[0])
end
assert(selfassign() == 708)

struct empty {}

terra emptystructs()
  var guard1 = 11
  var a : empty
  var b : empty
  var guard2 = 22
  a, b = b, a
  return guard1 * 100 + guard2
end
assert(emptystructs() == 1122)

struct withunion {
  tag : int
  union {
    i : int
    f : float
  }
}

terra unions() : {int, int, int, int}
  var a : withunion
  var b : withunion
  a.tag, a.i = 1, 2
  b.tag, b.i = 10, 20
  a, b = b, a
  return a.tag, a.i, b.tag, b.i
end
r = unions()
assert(r._0 == 10 and r._1 == 20 and r._2 == 1 and r._3 == 2)

terra vectors()
  var a = vector(1.f, 2.f, 3.f, 4.f)
  var b = vector(10.f, 20.f, 30.f, 40.f)
  a, b = b, a
  return int(a[0]) * 100 + int(b[0])
end
assert(vectors() == 1001)

-- A right hand side whose evaluation spans more than one basic block, so the
-- read of b and the write of b land in different blocks. The true branch also
-- clobbers b after it has been read, which the copy must not pick up.
terra acrossblocks(c : bool)
  var a, b = vec {1}, vec {10}
  a, b = b, [
    quote
      var t : vec
      if c then b = vec {99}  t = vec {5} else t = vec {7} end
    in
      t
    end
  ]
  return a.x * 100 + b.x
end
assert(acrossblocks(true) == 1005)
assert(acrossblocks(false) == 1007)

local ga = global(vec)
local gb = global(vec)

terra globals()
  ga, gb = vec {1}, vec {10}
  ga, gb = gb, ga
  return ga.x * 100 + gb.x
end
assert(globals() == 1001)

-- Repeated in a loop, which is where the original bug showed up. Note which
-- way round the symptom goes: correct code alternates, while the bug collapses
-- both variables to the same value on the first iteration and stays there.
terra inloop(n : int)
  var a, b = vec {1}, vec {10}
  for i = 0, n do
    a, b = b, a
  end
  return a.x * 100 + b.x
end
assert(inloop(1) == 1001)
assert(inloop(2) == 110)
assert(inloop(3) == 1001)
