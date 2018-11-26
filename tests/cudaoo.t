if not terralib.cudacompile then
    print("CUDA not enabled, not performing test...")
    return
end
if os.getenv("CI") then
	print("Running in CI environment without a GPU, not performing test...")
	return
end
C = terralib.includec("cuda_runtime.h")

cudalib.linkruntime()

terra foo()
    var stuff : &opaque
    C.cudaMalloc(&stuff,sizeof(int))
    return stuff
end

local a = foo()

terra blank() end
terralib.cudacompile { blank = blank }

assert(0 == C.cudaMemset(a,0,4))
