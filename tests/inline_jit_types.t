-- Inlining across the argument and return shapes Terra's C calling convention
-- handles specially: aggregates passed in registers, aggregates passed in
-- memory (byval/sret), arrays, pointers, and unit returns. These take different
-- paths through CCallingConv, so an inliner bug can easily show up in one and
-- not the others. Also covers inlining a C function into Terra in the JIT --
-- inline_c.t covers the same thing for saveobj, which uses a different pipeline.
local I = require("inlinelib")
print("inline_jit_types:")

-- Small struct: returned in registers on most targets.
struct TySmall { a : int, b : int }
terra ty_mksmall(a : int, b : int) return TySmall { a, b } end
terra ty_sumsmall(a : int, b : int)
    var s = ty_mksmall(a, b)
    return s.a + s.b
end
assert(ty_sumsmall(3, 4) == 7)
I.assertinlined("small struct by value", I.body(ty_sumsmall), {ty_mksmall})

-- Large struct: goes through memory, i.e. byval/sret.
struct TyBig { a : int, b : int, c : int, d : int, e : int, f : int, g : int, h : int }
terra ty_mkbig(seed : int)
    return TyBig { seed, seed+1, seed+2, seed+3, seed+4, seed+5, seed+6, seed+7 }
end
terra ty_takebig(v : TyBig) return v.a + v.d + v.h end
terra ty_usebig(seed : int) return ty_takebig(ty_mkbig(seed)) end
assert(ty_usebig(1) == 1 + 4 + 8)
I.assertinlined("large struct (byval/sret)", I.body(ty_usebig),
                {ty_mkbig, ty_takebig})

-- Array-typed values.
terra ty_mkarr(x : int)
    var a : int[4]
    a[0], a[1], a[2], a[3] = x, x+1, x+2, x+3
    return a
end
terra ty_usearr(x : int)
    var a = ty_mkarr(x)
    return a[0] + a[3]
end
assert(ty_usearr(10) == 23)
I.assertinlined("array by value", I.body(ty_usearr), {ty_mkarr})

-- Pointer arguments, i.e. mutation through the callee, and a unit return.
terra ty_bump(p : &int, by : int)
    @p = @p + by
end
terra ty_usebump(x : int)
    var v = x
    ty_bump(&v, 5)
    ty_bump(&v, 7)
    return v
end
assert(ty_usebump(1) == 13)
I.assertinlined("pointer arg, unit return", I.body(ty_usebump), {ty_bump})

-- Multiple return values.
terra ty_divmod(a : int, b : int) return a / b, a % b end
terra ty_usedivmod(a : int, b : int)
    var q, r = ty_divmod(a, b)
    return q * 100 + r
end
assert(ty_usedivmod(17, 5) == 302)
I.assertinlined("multiple return values", I.body(ty_usedivmod), {ty_divmod})

-- A C callee going through the JIT inliner.
--
-- Whether the C function is actually inlined is deliberately not asserted.
-- Clang's choice of linkage for a C `inline` definition varies by target and by
-- clang version, and an interposable definition (weak, linkonce) may not be
-- inlined at all -- so the outcome differs across the platforms Terra supports.
-- This is not specific to the manual inliner: LLVM 12, which still drives the
-- legacy inliner, declines to inline it just the same. What is checked here is
-- that a cross-language callee compiles and runs correctly through the
-- inliner; inline_c.t covers C inlining end to end via saveobj.
local Cinl = terralib.includecstring[[
inline int ty_cadd(int a, int b) { return a + b; }
]]
terra ty_usec(x : int) return Cinl.ty_cadd(x, 5) end
assert(ty_usec(3) == 8)
I.body(ty_usec)
print(string.format("  %-44s %s", "C callee (inlining is not portable)", "ok"))
