-- The attributes that steer the JIT inliner: setinlined(true/false) and
-- setoptimized(false). The two suppression cases are the controls for this
-- whole family of tests -- they keep passing when the inliner is broken, so if
-- the positive checks fail while these still pass, inlining is genuinely off
-- rather than the detection being wrong.
local I = require("inlinelib")
print("inline_jit_attrs:")

local C = terralib.includec("stdio.h")

-- setinlined(true) puts alwaysinline on the callee.
local attr_shouty = terra()
    C.printf("") C.printf("") C.printf("") C.printf("") C.printf("")
    C.printf("") C.printf("") C.printf("") C.printf("") C.printf("")
end
attr_shouty:setname("attr_shouty")
attr_shouty:setinlined(true)
terra attr_usesshouty()
    attr_shouty()
    attr_shouty()
    return 4
end
assert(attr_usesshouty() == 4)
I.assertinlined("setinlined(true) callee", I.body(attr_usesshouty), {attr_shouty})

-- setinlined(false) puts noinline on the callee: it must survive as a call even
-- though it is small enough that the cost model would otherwise take it.
terra attr_noinline(x : int) return x + 1 end
attr_noinline:setinlined(false)
terra attr_usesnoinline(x : int) return attr_noinline(x) end
assert(attr_usesnoinline(10) == 11)
I.assertnotinlined("setinlined(false) callee", I.body(attr_usesnoinline),
                   {attr_noinline})

-- setoptimized(false) puts optnone on the *caller*, so nothing may be inlined
-- into it.
terra attr_plain(x : int) return x + 1 end
terra attr_optnone(x : int) return attr_plain(x) end
attr_optnone:setoptimized(false)
assert(attr_optnone(10) == 11)
I.assertnotinlined("setoptimized(false) caller", I.body(attr_optnone), {attr_plain})

-- setoptimized(false) also implies noinline, so such a function is not inlined
-- into its own callers either.
terra attr_optnone2(x : int) return x + 1 end
attr_optnone2:setoptimized(false)
terra attr_callsoptnone(x : int) return attr_optnone2(x) + 1 end
assert(attr_callsoptnone(10) == 12)
I.assertnotinlined("optnone function as a callee", I.body(attr_callsoptnone),
                   {attr_optnone2})

-- Mixing the two in one caller: the plain callee goes, the noinline one stays.
terra attr_small(x : int) return x * 2 end
terra attr_blocked(x : int) return x * 3 end
attr_blocked:setinlined(false)
terra attr_mixed(x : int) return attr_small(x) + attr_blocked(x) end
assert(attr_mixed(4) == 20)
local mixed = I.body(attr_mixed)
I.assertinlined("mixed caller, inlinable callee", mixed, {attr_small})
I.assertnotinlined("mixed caller, noinline callee", mixed, {attr_blocked})
