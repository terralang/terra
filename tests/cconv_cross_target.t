-- The C calling convention must be chosen from the target we are generating
-- code for, never from the platform Terra itself was compiled on. This test
-- cross-compiles the same functions to several targets and checks that each
-- one gets its own ABI, so it fails the same way no matter which host runs it.

local function mkstruct(name, fields)
  local st = terralib.types.newstruct(name)
  for i, f in ipairs(fields) do
    st.entries:insert { field = "f" .. i, type = f }
  end
  return st
end

-- One "identity" function per shape: the signature Terra gives it is exactly
-- the ABI decision we want to observe.
local shapes = {
  i8x3 = { int8, int8, int8 },                  -- 3 bytes: not a whole register
  i32x3 = { int32, int32, int32 },              -- 12 bytes: two eightbytes
  f = { float },                                -- a lone float in a struct
  fx2 = { float, float },                       -- 8 bytes, all float
  dx2 = { double, double },                     -- 16 bytes, all double
  dx3 = { double, double, double },             -- 24 bytes: too big for registers
  dx5 = { double, double, double, double,       -- five members: past AArch64's
          double },                             --   HFA limit but not PPC64's
  i64x5 = { int64, int64, int64, int64, int64 },-- 40 bytes: indirect everywhere
}

local fns = {}
for name, fields in pairs(shapes) do
  local T = mkstruct(name, fields)
  fns["id_" .. name] = terra(x : T) : T return x end
end

local function irfor(triple)
  local ir = terralib.saveobj(nil, "llvmir", fns, nil,
                              terralib.newtarget { Triple = triple })
  local sigs = {}
  for line in ir:gmatch("[^\n]+") do
    local name = line:match("^define .*@(id_[%w_]+)%(")
    if name then sigs[name] = line end
  end
  return sigs
end

local failures = 0
local function check(triple, sigs, fn, what, ok)
  local sig = sigs[fn]
  if not sig then
    print(("FAIL %s: %s was not emitted"):format(triple, fn))
    failures = failures + 1
  elseif not ok(sig) then
    print(("FAIL %s: %s should %s\n     got: %s"):format(triple, fn, what, sig))
    failures = failures + 1
  end
end

local function returns(pattern)
  -- the return type sits between "define" (plus any linkage words) and the name
  return function(sig) return sig:match("define .*" .. pattern .. " @id_") ~= nil end
end
local function has(word)
  return function(sig) return sig:find(word, 1, true) ~= nil end
end
local function lacks(word)
  return function(sig) return sig:find(word, 1, true) == nil end
end

-- System V on x86-64: aggregates up to 16 bytes are split into two eightbytes
-- and classified per half, so an all-float eightbyte travels in an SSE
-- register. Anything larger is passed byval.
do
  local t = "x86_64-unknown-linux-gnu"
  local sigs = irfor(t)
  check(t, sigs, "id_i8x3", "be coerced to i24", returns("i24"))
  check(t, sigs, "id_f", "keep its float class", returns("float"))
  check(t, sigs, "id_fx2", "use an SSE register pair", returns("<2 x float>"))
  check(t, sigs, "id_dx2", "return two doubles in registers",
        returns("{ double, double }"))
  check(t, sigs, "id_i32x3", "return an eightbyte pair", returns("{ i64, i32 }"))
  check(t, sigs, "id_dx3", "be returned indirectly", has("sret"))
  check(t, sigs, "id_dx3", "be passed byval", has("byval"))
  check(t, sigs, "id_i64x5", "be passed byval", has("byval"))
end

-- Microsoft x64: an aggregate is passed directly only when its size is exactly
-- 1, 2, 4 or 8 bytes, and then always through an integer register. Everything
-- else goes indirectly, and the caller (not the callee) owns the copy, so the
-- pointer is not marked byval.
do
  local t = "x86_64-pc-windows-msvc"
  local sigs = irfor(t)
  check(t, sigs, "id_i8x3", "be passed indirectly", has("sret"))
  check(t, sigs, "id_f", "be coerced to an integer", returns("i32"))
  check(t, sigs, "id_fx2", "be coerced to an integer", returns("i64"))
  check(t, sigs, "id_dx2", "be passed indirectly", has("sret"))
  check(t, sigs, "id_i32x3", "be passed indirectly", has("sret"))
  check(t, sigs, "id_dx3", "be passed indirectly", has("sret"))
  for fn in pairs(shapes) do
    check(t, sigs, "id_" .. fn, "never be marked byval", lacks("byval"))
  end
end

-- AArch64 passes a homogeneous float aggregate of up to four members in
-- registers as an array, and marks an indirectly passed aggregate noundef
-- rather than byval. This is keyed on the architecture, so it has to hold for
-- both a Linux and a Darwin AArch64 target.
for _, t in ipairs { "aarch64-unknown-linux-gnu", "aarch64-apple-darwin" } do
  local sigs = irfor(t)
  check(t, sigs, "id_fx2", "pass an all-float pair as an array", has("[2 x float]"))
  check(t, sigs, "id_dx3", "keep a three-double HFA in registers",
        returns("%[3 x double%]"))
  check(t, sigs, "id_dx5", "spill a five-member HFA, which is past AArch64's limit "
        .. "of four (PPC64 allows eight)", has("sret"))
  check(t, sigs, "id_i64x5", "be passed indirectly", has("sret"))
  check(t, sigs, "id_i64x5", "not use byval", lacks("byval"))
end

-- PPC64 ELFv2 runs through the same classifier as AArch64 but with its own
-- limits, so the two have to stay distinguishable: a homogeneous float
-- aggregate rides in registers up to eight members rather than four, and
-- aggregates are packed as arrays rather than SysV eightbyte pairs. Returns
-- still only get two registers, so anything past 16 bytes is indirect.
do
  local t = "powerpc64le-unknown-linux-gnu"
  local sigs = irfor(t)
  check(t, sigs, "id_i8x3", "be coerced to i24", returns("i24"))
  check(t, sigs, "id_fx2", "pass an all-float pair as an array",
        returns("%[2 x float%]"))
  check(t, sigs, "id_dx2", "pass an all-double pair as an array, not as the SysV "
        .. "pair of doubles", returns("%[2 x double%]"))
  check(t, sigs, "id_dx3", "keep a three-double HFA in registers",
        returns("%[3 x double%]"))
  check(t, sigs, "id_dx5", "keep a five-member HFA in registers, where AArch64 "
        .. "spills it", returns("%[5 x double%]"))
  check(t, sigs, "id_i32x3", "return 12 bytes in registers", lacks("sret"))
  check(t, sigs, "id_i64x5", "return 40 bytes indirectly, since a return gets "
        .. "only two registers", has("sret"))
end

assert(failures == 0, failures .. " calling convention checks failed")
print("all cross-target calling convention checks passed")
