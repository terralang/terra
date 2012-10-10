
local IO = terralib.includec("stdio.h")
local stdlib = terralib.includec("stdlib.h")

local NB = 64
local V = 8
terra my_sgemm(M : int, N : int, K : int, alpha : float, A : &float, lda : int, B : &float, ldb : int, 
	           beta : float, C : &float, ldc : int)
	var TB = stdlib.malloc(K * N * sizeof(float)):as(&float)
	for k = 0,K do
		for n = 0,N do
			TB[n*K + k] = B[k*ldb + n]
		end
	end

	for mm = 0,M,NB do
		for nn = 0, N,NB do
			for m = mm,mm+NB do
				for n = nn,nn+NB do
					var v : vector(float,V) = 0.f
					for k = 0, K, V do
						var entrya = &A[m*lda + k]
						var entryb = &TB[n*K + k]
						v = v + @entrya:as(&vector(float,V)) * @entryb:as(&vector(float,V))
						--var entryc = &A[m*lda + k + V]
						--var entryd = &TB[n*K + k + V]
						--v = v + @entryc:as(&vector(float,V)) * @entryd:as(&vector(float,V))  
					end
					var r = 0.f
					for i = 0, V do
						r = r + v[i]
					end
					C[m*ldc + n] = r
				end
			end
		end
	end
	stdlib.free(TB)
end


terralib.saveobj("my_sgemm.o", {my_sgemm = my_sgemm})