-- Call graph shapes: the JIT inliner is driven once per strongly connected
-- component, so vary how many SCCs there are and how they are connected.
-- See tests/inlinelib.lua for how inlining is detected.
local I = require("inlinelib")

-- Two SCCs: one callee, one caller, one call site. The simplest thing that can
-- possibly work.
terra scc_add3(a : int, b : int, c : int) return a + b + c end
terra scc_one(x : int) return scc_add3(x, 1, 2) end
assert(scc_one(10) == 13)
I.assertinlined("2 SCCs, 1 call site", I.body(scc_one), {scc_add3})

-- Two SCCs, but the callee is used from several sites in the same caller. This
-- inlines repeatedly into one function, which is where stale cached analyses
-- would show up.
terra scc_multi(x : int)
    return scc_add3(x, 1, 2) + scc_add3(x, 3, 4) + scc_add3(x, 5, 6)
end
assert(scc_multi(10) == 51)
I.assertinlined("2 SCCs, 3 call sites", I.body(scc_multi), {scc_add3})

-- Four SCCs in a chain. Only the innermost call is visible when the outermost
-- function is emitted; the rest are exposed by inlining, so this exercises the
-- worklist and the inline history that bounds it.
terra scc_l1(x : int) return x + 1 end
terra scc_l2(x : int) return scc_l1(x) * 2 end
terra scc_l3(x : int) return scc_l2(x) + 3 end
terra scc_l4(x : int) return scc_l3(x) * 5 end
assert(scc_l4(10) == 125)
I.assertinlined("4 SCCs, chain", I.body(scc_l4), {scc_l1, scc_l2, scc_l3})

-- Four SCCs in a diamond: two independent callers of a shared leaf, joined.
terra scc_leaf(x : int) return x * 3 end
terra scc_left(x : int) return scc_leaf(x) + 1 end
terra scc_right(x : int) return scc_leaf(x) - 1 end
terra scc_top(x : int) return scc_left(x) + scc_right(x) end
assert(scc_top(10) == 60)
I.assertinlined("4 SCCs, diamond", I.body(scc_top), {scc_leaf, scc_left, scc_right})

-- A callee with control flow, so inlining has to split the caller's block
-- rather than splice a single basic block in.
terra scc_branchy(x : int)
    if x < 0 then
        return -x
    elseif x == 0 then
        return 100
    else
        return x * 2
    end
end
terra scc_usesbranchy(x : int) return scc_branchy(x) + scc_branchy(-x) end
assert(scc_usesbranchy(5) == 15 and scc_usesbranchy(0) == 200)
I.assertinlined("2 SCCs, multi-block callee", I.body(scc_usesbranchy), {scc_branchy})

-- An indirect call has no known callee. It must be left alone rather than
-- crash the inliner, and the code still has to work.
terra scc_indirect(f : {int} -> int, x : int) return f(x) + f(x) end
terra scc_callsindirect(x : int) return scc_indirect(scc_leaf, x) end
assert(scc_callsindirect(4) == 24)
I.body(scc_indirect) -- the inliner saw an unresolvable callee and survived
print("  indirect call survived")
