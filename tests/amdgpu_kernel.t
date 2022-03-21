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
  x : int32,
  y : int32,
}

terra sub_i2(a : i2, b : i2)
  return [i2]({ a.x - b.x, a.y - b.y })
end

-- Allocas use an address space in AMDGPU target, make sure that is respected.
terra f(y : i2)
  var i = [i2]({0, 0})
  var x = sub_i2(i, y)
end
f:setcallingconv("amdgpu_kernel")

struct i3 {
  x : int64,
  y : int64,
  z : int64,
}

terra sub_i3(a : i3, b : i3)
  return [i3]({ a.x - b.x, a.y - b.y, a.z - b.z })
end

-- Same with a struct large enough to force passing by value.
terra g(y : i3)
  var i = [i3]({0, 0, 0})
  var x = sub_i3(i, y)
end
g:setcallingconv("amdgpu_kernel")

local ir = terralib.saveobj(nil, "llvmir", {saxpy=saxpy, f=f, g=g}, {}, amd_target)
assert(string.match(ir, "define dso_local amdgpu_kernel void @saxpy"))
