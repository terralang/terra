-- SCCs that contain cycles. Without a call graph to lean on, the JIT inliner
-- bounds itself with an inline-history chain, so mutually recursive groups are
-- the case most likely to loop forever or blow up.
--
-- Recursive calls themselves are deliberately not asserted on: whether LLVM
-- unrolls one level of a cycle is a cost-model detail that varies by version.
-- What is asserted is that a cyclic SCC still gets its *non-recursive* callees
-- inlined, which is the part that would break if the inliner bailed on cycles.
--
-- These do declare return types, because inference does not always terminate
-- through a recursive cycle.
local I = require("inlinelib")
print("inline_jit_recursive:")

terra rec_helper(x : int) return x + 1 end

-- One SCC of one function, with a self-edge.
terra rec_fact(n : int) : int
    if n <= 1 then
        return rec_helper(0)
    end
    return n * rec_fact(n - 1)
end
assert(rec_fact(5) == 120)
I.assertinlined("1-function SCC (self-recursive)", I.body(rec_fact), {rec_helper})

-- One SCC of two functions.
local terra rec_odd :: {int} -> int
terra rec_even(n : int) : int
    if n == 0 then
        return rec_helper(0)
    end
    return rec_odd(n - 1)
end
terra rec_odd(n : int) : int
    if n == 0 then
        return rec_helper(-1)
    end
    return rec_even(n - 1)
end
assert(rec_even(10) == 1 and rec_even(7) == 0 and rec_odd(7) == 1)
I.assertinlined("2-function SCC", I.body(rec_even), {rec_helper})
I.assertinlined("2-function SCC (other member)", I.body(rec_odd), {rec_helper})

-- One SCC of three functions.
local terra rec3_b :: {int} -> int
local terra rec3_c :: {int} -> int
terra rec3_a(n : int) : int
    if n <= 0 then
        return rec_helper(0)
    end
    return rec3_b(n - 1) + rec_helper(1)
end
terra rec3_b(n : int) : int
    if n <= 0 then
        return rec_helper(0)
    end
    return rec3_c(n - 1) + rec_helper(1)
end
terra rec3_c(n : int) : int
    if n <= 0 then
        return rec_helper(0)
    end
    return rec3_a(n - 1) + rec_helper(1)
end
assert(rec3_a(6) == 13)
I.assertinlined("3-function SCC", I.body(rec3_a), {rec_helper})

-- alwaysinline on a recursive function: the attribute cannot be honoured all
-- the way down, so this checks the inliner stops rather than obeying forever.
terra rec_ai(n : int) : int
    if n <= 0 then
        return 0
    end
    return 1 + rec_ai(n - 1)
end
rec_ai:setinlined(true)
terra rec_usesai() return rec_ai(4) end
assert(rec_usesai() == 4)
print("  alwaysinline recursion terminated")

-- A cycle reached only through a non-recursive entry point, so the entry point
-- is its own SCC and the cycle is another.
terra rec_entry(n : int) return rec_even(n) + rec_helper(0) end
assert(rec_entry(4) == 2)
I.assertinlined("SCC calling a cyclic SCC", I.body(rec_entry), {rec_helper})
