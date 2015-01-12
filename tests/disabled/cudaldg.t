if not terralib.cudacompile then
	print("CUDA not enabled, not performing test...")
	return
end

local tid = terralib.intrinsic("llvm.nvvm.read.ptx.sreg.tid.x",{} -> int)

local ldgf = terralib.intrinsic("llvm.nvvm.ldg.global.f.f64", &double -> double)

C = terralib.includecstring [[
#include <stdio.h>
#include <cuda.h>
#include <cuda_runtime.h>
#include <string.h>
]]

vprintf = terralib.externfunction("cudart:vprintf", {&int8,&int8} -> int)

foo = terra(result : &double)
    var t = tid()
    var rr = ldgf(result + t)
    vprintf("%f\n",[&int8](&rr))    
end

terralib.includepath = terralib.includepath..";/usr/local/cuda/include"

sync = terralib.externfunction("cudaThreadSynchronize", {} -> int)

local R = terralib.cudacompile({ foo = foo })

terra doit(N : int)
	var d_buffer : &double
	C.cudaMalloc([&&opaque](&d_buffer),N*sizeof(double))
	
	var h_buffer = arrayof(double,0,1,2,3,4,5,6,7,8,9,10)
	C.cudaMemcpy(d_buffer,&h_buffer[0],sizeof(double)*N, C.cudaMemcpyHostToDevice)
	
	var launch = terralib.CUDAParams { 1,1,1, N,1,1, 0, nil }
	R.foo(&launch,d_buffer)
	sync()
	C.printf("and were done\n")
end

doit(10)
