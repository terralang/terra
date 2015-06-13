local ffi = require("ffi")
if ffi.os == "Windows" then
	return
end
local adjust = 0
local acc = terralib.includecstring[[
	void cblas_dgemm(int, int,
                 int, const int M, const int N,
                 const int K, const double alpha, const double *A,
                 const int lda, const double *B, const int ldb,
                 const double beta, double *C, const int ldc);
]]
ffi.load("/System/Library/Frameworks/Accelerate.framework/Accelerate")

function CalcTime(fn)
	local begin = terralib.currenttimeinseconds()
	local current
	local times = 0
	repeat
		fn()
		current = terralib.currenttimeinseconds()
		times = times + 1
	until (current - begin) > 0.2
	return (current - begin - adjust*times) / times 
end
local terra empty() end
adjust = CalcTime(empty) --calculate function call overhead and subtract from tests


local MTH = {}

local function referenceblas(M,K,N,A,B,C)
	acc.cblas_dgemm(101,111,111,M,N,K,1.0,A,K,B,N,0.0,C,N)
end

function MTH.timefunctions(typstring,M,K,N,...)
	local ctyp = typstring.."[?] __attribute__((aligned(64)))"
	local A,B = ffi.new(ctyp,M*K), ffi.new(ctyp,K*N)
	for m = 0, M-1 do
		for k = 0, K-1 do
			A[m*K + k] = math.random(0,9)
		end
	end
	for k = 0, K-1 do
		for n = 0, N-1 do
			B[k*N + n] = math.random(0,9)
		end
	end
	local fns = {...}
	local Cs = {}
	for i,fn in ipairs(fns) do
		local C = ffi.new(ctyp,M*N)
		for j = 0, M * N - 1 do
			C[j] = -1
		end	
		Cs[i] = C
	end
	
	local results = {}
	for i,fn in ipairs(fns) do
		local C = Cs[i]
		local tocall = function() fn(M,K,N,A,B,C) end
		tocall()
		results[i] = M*N*K*2.0*1e-9 / CalcTime(tocall)
		
		if i ~= 1 then
			local C0 = Cs[1]
			local C1 = Cs[i]
			local c = 0
			for m = 0, M-1 do
				for n = 0, N-1 do
					if C0[c]~= C1[c] then
						return false
					end
					c = c + 1
				end
			end
		end
	end
	return true,results
end
--terra my_dgemm(gettime : {} -> double, M : int, N : int, K : int, alpha : double, A : &double, lda : int, B : &double, ldb : int, 
--	           beta : double, C : &double, ldc : int)

function MTH.comparetoaccelerate(NB,myfn)

	for i = NB, math.huge, NB do
		local m,n,k = i,i,i
		io.write(("%d %d %d "):format(m,n,k))
		local s,r = MTH.timefunctions("double",m,n,k,referenceblas,myfn)
		if s then
			print(unpack(r))
		else
			print(" <error> ")
		end
		if m*n + m*k + n*k > 3*1024*1024 then
			break
		end
	end
end

return MTH
