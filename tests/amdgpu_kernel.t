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

-- Run some tests to make sure AMDGPU codegen is working. In particular:
--  * AMDGPU uses a non-zero address space for allocas
--  * AMDGPU requires structs to be passed by registers rather than the stack.

struct i1 {
  x : int32,
}

terra sub_i1(a : i1, b : i1)
  return [i1]({ a.x - b.x })
end

struct i2 {
  x : int32,
  y : int32,
}

terra sub_i2(a : i2, b : i2)
  return [i2]({ a.x - b.x, a.y - b.y })
end

-- Make sure this struct is large enough to trip over size limits if
-- we don't do the right thing.
struct i3 {
  x : int64,
  y : int64,
  z : int64,
}

terra sub_i3(a : i3, b : i3)
  return [i3]({ a.x - b.x, a.y - b.y, a.z - b.z })
end

-- Nested structs.
struct i3p {
  p : i3,
}

terra sub_i3p(a : i3p, b : i3p)
  return [i3p]({ sub_i3(a.p, b.p) })
end

terra f(y : i1)
  var i = [i1]({0})
  var x = sub_i1(i, y)
end
f:setcallingconv("amdgpu_kernel")

terra g(y : i2)
  var i = [i2]({0, 0})
  var x = sub_i2(i, y)
end
g:setcallingconv("amdgpu_kernel")

terra h(y : i3)
  var i = [i3]({0, 0, 0})
  var x = sub_i3(i, y)
end
h:setcallingconv("amdgpu_kernel")

terra k(y : i3p)
  var i = [i3p]({ [i3]({ 0, 0, 0}) })
  var x = sub_i3p(i, y)
end
k:setcallingconv("amdgpu_kernel")

-- Address of stack variable.
terra m(z : &int)
  var x = 0
  var y = &x
  @y = 123
  z[0] = x
end
m:setcallingconv("amdgpu_kernel")

local ir = terralib.saveobj(nil, "llvmir", {saxpy=saxpy, f=f, g=g, h=h, k=k, m=m}, {}, amd_target)
assert(string.match(ir, "define dso_local amdgpu_kernel void @saxpy"))
