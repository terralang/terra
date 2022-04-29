if terralib.llvm_version < 90 then
  print("LLVM is too old, skipping AMD GPU test...")
  return
end

-- This tests a bug that occurred when using C structs imported from a
-- header file. The structs were associated with a certain target, and
-- if used from a different target could cause issues.

local c = terralib.includecstring [[
typedef struct t {
  int x;
  int y;
} t;
]]

terra f()
  var s : c.t
  s.x = 123
  s.y = 456
  return s.x + s.y
end

-- Works on CPU.
print(f())
assert(f() == 579)

local arch = 'gfx908'
local amd_target = terralib.newtarget {
  Triple = 'amdgcn-amd-amdhsa',
  CPU = arch,
  FloatABIHard = true,
}

-- Make sure it also works on AMD GPU.
print(terralib.saveobj(nil, "llvmir", {f=f}, nil, amd_target))
