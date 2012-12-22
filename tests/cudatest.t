if not terralib.cudacompile then
	print("CUDA not enabled, not performing test...")
	return
end

--our very simple cuda kernel
--more work needs to be done to expose the right CUDA intrinsics
--to do more compilicated things
terra foo(result : &int)
	@result = 5
end

local C = terralib.includec("cuda_runtime.h")
local R = terralib.cudacompile({ foo = foo, bar = foo })

terra doit()
	var data : &uint8
	C.cudaMalloc(&data,sizeof(int))
	var launch = terralib.CUDAParams { 1,1,1, 1,1,1, 0, nil }
	R.bar(&launch,data:as(&int))
	var result : int
	C.cudaMemcpy(&result,data,sizeof(int),2)
	return result
end

local test = require("test")
test.eq(doit(),5)