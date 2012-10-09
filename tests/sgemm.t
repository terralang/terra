
local IO = terralib.includec("stdio.h")

terra my_sgemm(M : int, N : int, K : int, alpha : float, A : &float, lda : int, B : &float, ldb : int, 
	           beta : float, C : &float, ldc : int)
	for m = 0,M do
		for n = 0, N do
			var v = 0.f
			for k = 0, K do
				v = v + A[m*lda + k] * B[k*ldb + n] 
			end
			C[m*ldc + n] = v
		end
	end
end


terralib.saveobj("my_sgemm.o", {my_sgemm = my_sgemm})