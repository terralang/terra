if terralib.llvm_version < 90 then
  print("LLVM is too old, skipping AMD GPU test...")
  return
end

local arch = 'gfx908'
local amd_target = terralib.newtarget {
  Triple = 'amdgcn-amd-amdhsa',
  CPU = arch,
  FloatABIHard = true,
}

local wgx = terralib.intrinsic("llvm.amdgcn.workgroup.id.x",{} -> int32)
local wix = terralib.intrinsic("llvm.amdgcn.workitem.id.x",{} -> int32)

local workgroup_size = 256

terra saxpy(num_elements : uint64, alpha : float,
            x : &float, y : &float, z : &float)
  var idx = wgx() * workgroup_size + wix()
  if idx < num_elements then
    z[idx] = z[idx] + alpha * x[idx] + y[idx]
  end
end
saxpy:setcallingconv("amdgpu_kernel")

struct i2 {
  x : int,
  y : int,
}
terra f()
  -- Allocas use an address space in AMDGPU target, make sure that is respected.
  var x = i2 {1, 1}
end
f:setcallingconv("amdgpu_kernel")

local ir = terralib.saveobj(nil, "llvmir", {saxpy=saxpy, f=f}, {}, amd_target)
assert(string.match(ir, "define dso_local amdgpu_kernel void @saxpy"))
