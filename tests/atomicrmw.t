local has_syncscope = terralib.llvm_version >= 50
-- FIXME: Setting alignment causes a crash on Linux
local has_align = false -- terralib.llvm_version >= 110
local has_fadd = terralib.llvm_version >= 90



terra atomic_add(x : &int, y : int, z : int, w : int, u : int)
  terralib.atomicrmw("add", x, y, {ordering = "seq_cst"})
  terralib.atomicrmw("add", x, z, {ordering = "acq_rel"})
  escape
    if has_syncscope and has_align then
      emit quote
        terralib.atomicrmw("add", x, w, {ordering = "monotonic", syncscope = "singlethread", align = 1})
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
  terralib.atomicrmw("add", x, u, {ordering = "monotonic", isvolatile = true})
end
atomic_add:printpretty(false)
atomic_add:disas()

terra add()
  var i : int = 1

  atomic_add(&i, 20, 300, 4000, 50000)

  return i
end

print(add())
assert(add() == 54321)



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
