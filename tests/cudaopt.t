-- Device-side (PTX) optimization.
--
-- The PTX pipeline in moduleToPTX is separate from both the host JIT and
-- saveobj, so it can lose its optimizations without any host-side test
-- noticing. That is exactly what happened from LLVM 17: the port to the new
-- pass manager dropped the module passes and left only code generation, so
-- device code stopped being optimized at all for several releases.
--
-- Unlike the other cuda*.t tests, this one needs the CUDA toolkit (libnvvm and
-- libdevice) but *not* a GPU or the driver -- generating PTX never opens
-- libcuda -- so it deliberately does not skip in CI, which is where a
-- regression like this should get caught.
--
-- Portability: every assertion is about a whole class of PTX construct (is
-- there a call left to this function, is there a branch at all) rather than an
-- exact instruction sequence, so none of it depends on the LLVM version, the
-- CUDA version, the host OS, or the host architecture.

if not terralib.cudacompile then
    print("CUDA not enabled, not performing test...")
    return
end

-- We can generate PTX without querying the device, so the target is fixed
-- rather than taken from the local GPU. The exact choice doesn't make much
-- difference. We choose compute capability 7.5 (Turing) because it's the
-- oldest architecture CUDA 13 still supports.
local ARCH = 75

local tid = cudalib.nvvm_read_ptx_sreg_tid_x

local function ptxfor(name, kernel)
    local ptx = cudalib.toptx({ [name] = kernel }, nil, ARCH)
    assert(ptx and #ptx > 0, "no PTX generated for " .. name)
    return ptx
end

local function fail(label, msg, ptx)
    error(label .. ": " .. msg .. "\n--- PTX ---\n" .. ptx .. "\n-----------", 3)
end

-- A device function that survived inlining shows up in the PTX both as a .func
-- definition and as the target of a call, so its name being absent entirely is
-- the check.
local function assertinlined(label, ptx, callee)
    if ptx:find(callee, 1, true) then
        fail(label, "expected '" .. callee .. "' to be inlined into the kernel", ptx)
    end
    print(string.format("  %-46s inlined    %s", label, callee))
end

-- With the scalar pipeline running, a constant-trip-count loop is fully
-- unrolled and folded, leaving straight-line code. Without it the loop survives
-- as a branch: code generation alone cannot unroll.
local function assertstraightline(label, ptx)
    if ptx:match("%f[%w]bra%f[%W]") then
        fail(label, "expected the loop to be optimized away, but the PTX branches", ptx)
    end
    print(string.format("  %-46s straight-line (loop unrolled)", label))
end

-- A device helper is inlined into the kernel that calls it.
local terra opt_scale(x : float)
    return x * 3.0f + 1.0f
end
terra opt_kern_inline(out : &float)
    out[tid()] = opt_scale([float](tid()))
end
assertinlined("device helper", ptxfor("opt_kern_inline", opt_kern_inline), "opt_scale")

-- Two levels deep: the inner call only becomes visible once the outer one has
-- been inlined.
local terra opt_inner(x : float)
    return x + 1.0f
end
local terra opt_outer(x : float)
    return opt_inner(x) * 2.0f
end
terra opt_kern_chain(out : &float)
    out[tid()] = opt_outer([float](tid()))
end
local chain = ptxfor("opt_kern_chain", opt_kern_chain)
assertinlined("transitive helper (outer)", chain, "opt_outer")
assertinlined("transitive helper (inner)", chain, "opt_inner")

-- setinlined(true) has to be honoured on the device path too: cudalib.toptx
-- marks every kernel it wraps that way.
local terra opt_always(x : float)
    return x * x + x
end
opt_always:setinlined(true)
terra opt_kern_always(out : &float)
    out[tid()] = opt_always([float](tid()))
end
assertinlined("setinlined(true) helper",
              ptxfor("opt_kern_always", opt_kern_always), "opt_always")

-- The scalar optimization pipeline runs, not just the inliner.
terra opt_kern_loop(out : &float)
    var acc = 0.f
    for i = 0, 4 do
        acc = acc + [float](i) * 2.0f
    end
    out[tid()] = acc
end
assertstraightline("constant-trip loop", ptxfor("opt_kern_loop", opt_kern_loop))
