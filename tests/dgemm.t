
local IO = terralib.includec("stdio.h")
local stdlib = terralib.includec("stdlib.h")

local function isinteger(x) return math.floor(x) == x end




terra naivel1matmul(A : &double, B : &double, C : &double, lda : int, ldb : int, ldc : int, alpha : double)

	for m = 0, NB do
		for n = 0, NB do
			C[m*ldc + n] = alpha * C[m*ldc + n]
			for k = 0, NB do
				C[m*ldc + n] = C[m*ldc + n] + A[m*lda + k] * B[k*ldb + n]
			end
		end
	end

end

function symmat(name,I,...)
	if not I then return symbol(name) end
	local r = {}
	for i = 0,I-1 do
		r[i] = symmat(name..tostring(i),...)
	end
	return r
end


function genl1matmul(NB, NK, RM, RN, V)
	
	assert(isinteger(NB / (RN*V)))
	assert(isinteger(NB / RM))

	local terra vecload(data : &double, idx : int)
		var addr = &data[idx]
		return @addr:as(&vector(double,V))
	end
	local terra vecstore(data : &double, idx : int, v : vector(double,V))
		var addr = &data[idx]
		@addr:as(&vector(double,V)) = v
	end

	local A,B,C,mm,nn, alpha = symbol("A"),symbol("B"),symbol("C"),symbol("mn"),symbol("nn"),symbol("alpha")
	local lda,ldb,ldc = symbol("lda"),symbol("ldb"), symbol("ldc")
	local a,b,c = symmat("a",NB/V,RM), symmat("b",NB,RN), symmat("c",RM,RN)
	local kk = symbol("kk")
	
	local loadc,storec = terralib.newlist(),terralib.newlist()

	for m = 0, RM-1 do
		for n = 0, RN-1 do
			loadc:insert(quote
				var [c[m][n]] = alpha * vecload(C,(mm+m)*ldc + nn + n*V)
			end)
			storec:insert(quote
				vecstore(C,(mm+m)*ldc + nn + n*V,[c[m][n]])
			end)
		end
	end

	local calcc = terralib.newlist()
	
	for kb = 0, NK/V-1 do
		local kbV = kb*V
		for m = 0, RM-1 do
			calcc:insert(quote
				var [a[kb][m]] = vecload(A,(mm+m)*lda + kk + kbV)
			end)
		end
		for v = 0, V-1 do
			local k = kbV+v
			for n = 0, RN-1 do
				calcc:insert(quote
					var [b[k][n]] = vecload(B,(kk + k)*ldb + nn + n*V)
				end)
			end
			for m = 0, RM-1 do 
				for n = 0, RN-1 do
					calcc:insert(quote
						[c[m][n]] = [c[m][n]] + [a[kb][m]][v] * [b[k][n]]
					end)
				end
			end
		end
	end

	return terra([A] : &double, [B] : &double, [C] : &double, [lda] : int, [ldb] : int, [ldc] : int, [alpha] : double)
		for [mm] = 0, NB, RM do
			for [nn] = 0, NB,RN*V do
				[loadc];
				for [kk] = 0, NB, NK do
					[calcc];
				end
				[storec];
			end
		end
	end
end



local NB2 = 320
local NB = 40
local l1matmul = genl1matmul(NB,4, 2, 2, 4)

l1matmul:compile()
l1matmul:printpretty()


terra min(a : int, b : int)
	return terralib.select(a < b, a, b)
end

terra my_dgemm(gettime : {} -> double, M : int, N : int, K : int, alpha : double, A : &double, lda : int, B : &double, ldb : int, 
	           beta : double, C : &double, ldc : int)
	for mm = 0,M,NB2 do
		for nn = 0,N,NB2 do
			for kk = 0,K, NB2 do
				for m = mm,min(mm+NB2,M),NB do
					for n = nn,min(nn+NB2,N),NB do
						for k = kk,min(kk+NB2,K),NB do
							l1matmul(A + m*lda + k,
							         B + k*ldb + n,
							         C + m*ldc + n,
							         lda,ldb,ldc, terralib.select(k == 0,0,1))
						end
					end
				end
			end
		end
	end
end

my_dgemm:compile()
my_dgemm:printpretty()

terralib.saveobj("my_dgemm.o", {my_dgemm = my_dgemm})