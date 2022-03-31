terra atomic_add(x : &int, y : int, z : int, w : int, u : int)
  terralib.atomicrmw("add", x, y, {ordering = "monotonic"})
  terralib.atomicrmw("add", x, z, {ordering = "monotonic", syncscope = "singlethread"})
  terralib.atomicrmw("add", x, w, {ordering = "monotonic", align = 1})
  terralib.atomicrmw("add", x, u, {ordering = "monotonic", isvolatile = true})
end
atomic_add:printpretty(false)
atomic_add:disas()

terra atomic_fadd(x : &double, y : double)
  terralib.atomicrmw("fadd", x, y, {ordering = "monotonic"})
end
atomic_fadd:printpretty(false)
atomic_fadd:disas()

terra add()
  var i : int = 1

  atomic_add(&i, 20, 300, 4000, 50000)

  return i
end

terra fadd()
  var f : double = 1.0

  atomic_fadd(&f, 20.0)

  return f
end

print(add())
assert(add() == 54321)

print(fadd())
assert(fadd() == 21.0)
