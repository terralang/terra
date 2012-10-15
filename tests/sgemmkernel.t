
function symmat(name,I,...)
	if not I then return symbol(name) end
	local r = {}
	for i = 0,I-1 do
		r[i] = symmat(name..tostring(i),...)
	end
	return r
end


function genkernel(NB, RM, RN, V,alpha)

	local terra vecload(data : &float, idx : int)
		var addr = &data[idx]
		return @addr:as(&vector(float,V))
	end
	local terra vecstore(data : &float, idx : int, v : vector(float,V))
		var addr = &data[idx]
		@addr:as(&vector(float,V)) = v
	end

	local A,B,C,mm,nn = symbol("A"),symbol("B"),symbol("C"),symbol("mn"),symbol("nn")
	local lda,ldb,ldc = NB,NB,NB
	local a,b,c,caddr = symmat("a",RM), symmat("b",RN), symmat("c",RM,RN), symmat("caddr",RM,RN)
	local k = symbol("k")
	
	local loadc,storec = terralib.newlist(),terralib.newlist()

	for m = 0, RM-1 do
		for n = 0, RN-1 do
			loadc:insert(quote
				var [caddr[m][n]] = C + (mm+m)*ldc + nn + n*V
				var [c[m][n]] = alpha * @[caddr[m][n]]:as(&vector(float,V))
			end)
			storec:insert(quote
				@[caddr[m][n]]:as(&vector(float,V)) = [c[m][n]]
			end)
		end
	end

	local calcc = terralib.newlist()
	
	for n = 0, RN-1 do
		calcc:insert(quote
			var [b[n]] = @(&B[k*ldb + nn + n*V]):as(&vector(float,V))
		end)
	end
	for m = 0, RM-1 do
		calcc:insert(quote
			var [a[m]] = A[(mm+m)*lda + k]:as(vector(float,V))
		end)
	end
	for m = 0, RM-1 do 
		for n = 0, RN-1 do
			calcc:insert(quote
				[c[m][n]] = [c[m][n]] + [a[m]] * [b[n]]
			end)
		end
	end
	
	
	return terra([A] : &float, [B] : &float, [C] : &float)
		for [mm] = 0, NB, RM do
			for [nn] = 0, NB,RN*V do
				[loadc];
				for [k] = 0, NB do
					[calcc];
				end
				[storec];
			end
		end
	end
end

local NB = 32
local NB2 = 8 * NB

local V = 8

l1sgemm0 = genkernel(NB,2,4,V,0)
l1sgemm1 = genkernel(NB,2,4,V,1)

terra min(a : int, b : int)
	return terralib.select(a < b, a, b)
end

local stdlib = terralib.includec("stdlib.h")
local IO = terralib.includec("stdio.h")

terra my_sgemm(gettime : {} -> double, M : int, N : int, K : int, alpha : double, A : &float, lda : int, B : &float, ldb : int, 
	           beta : float, C : &float, ldc : int)
	
	var AA = stdlib.malloc(sizeof(float)*M*K):as(&float)
	var BB = stdlib.malloc(sizeof(float)*K*N):as(&float)
	var CC = stdlib.malloc(sizeof(float)*M*N):as(&float)

	var i = 0
	for mm = 0,M,NB do
		for kk = 0,K,NB do
			for m = mm,mm+NB do
				for k = kk,kk+NB,V do
					@(&AA[i]):as(&vector(float,V)) = @(&A[m*lda + k]):as(&vector(float,V))
					i = i + V
				end
			end
		end
	end
	i = 0 
	for kk = 0,K,NB do
		for nn = 0,N,NB do
			for k = kk,kk+NB do
				for n = nn,nn+NB,V do
					@(&BB[i]):as(&vector(float,V)) = @(&B[k*ldb + n]):as(&vector(float,V))
					i = i + V
				end
			end
		end
	end	

	for mm = 0,M,NB2 do
		for nn = 0,N,NB2 do
			for kk = 0,K, NB2 do
				for m = mm,min(mm+NB2,M),NB do
					for n = nn,min(nn+NB2,N),NB do
						for k = kk,min(kk+NB2,K),NB do
							--IO.printf("%d %d starting at %d\n",m,k,m*lda + NB*k)
							if k == 0 then
								l1sgemm0(AA + (m*lda + NB*k),
							         	 BB + (k*ldb + NB*n),
							             CC + (m*ldc + NB*n))
							else
								l1sgemm1(AA + (m*lda + NB*k),
							         	 BB + (k*ldb + NB*n),
							             CC + (m*ldc + NB*n))
							end
						end
					end
				end
			end
		end
	end

	i = 0
	for mm = 0,M,NB do
		for nn = 0,N,NB do
			for m = mm,mm+NB do
				for n = nn,nn+NB,V do
					@(&C[m*ldc + n]):as(&vector(float,V)) = @(&CC[i]):as(&vector(float,V))
					i = i + V
				end
			end
		end
	end	

	stdlib.free(AA)
	stdlib.free(BB)
	stdlib.free(CC)
end

terralib.saveobj("my_sgemmkernel.o", { my_sgemm = my_sgemm })