function terralib.cudacompile(module)
	local tbl = {}
	for k,v in pairs(module) do
		if not terra.isfunction(v) then
			error("module must contain only terra functions")
		end
		v:emitllvm()
		local definitions =  v:getdefinitions()
		if #definitions > 1 then
			error("cuda kernels cannot be polymorphic, but found polymorphic function "..k)
		end
		local fn = definitions[1]
		local success,typ = fn:peektype() -- calling gettype would JIT the function, which we don't want
		                            -- we should modify gettype to allow the return of a type for a non-jitted function
		assert(success)

		if #typ.returns ~= 0 then
			error(k..": kernels must return no arguments.")
		end

		for _,p in ipairs(typ.parameters) do
			if not p:ispointer() or p:isprimitive() then
				error(k..": kernels arguments can only be primitive types or pointers but kernel has type ", typ)
			end
		end
		tbl[k] = definitions[1]
	end
	--call into tcuda.cpp to perform compilation
	return terralib.cudacompileimpl(tbl)
end






--we need to use terra to write the function that JITs the right wrapper functions for CUDA kernels
--since this file is loaded as Lua, we use terra.loadstring to inject some terra code
local terracode = terra.loadstring [[
local C = terralib.includec("cuda.h")

struct terralib.CUDAParams {
	gridDimX : uint,  gridDimY : uint,  gridDimZ : uint,
	blockDimX : uint, blockDimY : uint, blockDimZ : uint,
	sharedMemBytes : uint, hStream :  C.CUstream
}

function terralib.cudamakekernelwrapper(fn,funcdata)
	local _,typ = fn:peektype()
	local arguments = typ.parameters:map(symbol)
	
	local paramctor = arguments:map(function(s) return `&s end)
	return terra(params : &terralib.CUDAParams, [arguments])
		
		var func : &C.CUfunction = funcdata:as(&C.CUfunction)
		var paramlist = arrayof(&uint8,[paramctor])
		return C.cuLaunchKernel(@func,params.gridDimX,params.gridDimY,params.gridDimZ,
		                             params.blockDimX,params.blockDimY,params.blockDimZ,
		                             params.sharedMemBytes, params.hStream,paramlist,nil)
	end
end 

]]
terracode()