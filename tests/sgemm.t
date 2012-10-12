
local IO = terralib.includec("stdio.h")
local stdlib = terralib.includec("stdlib.h")

haddavx = terralib.intrinsic("llvm.x86.avx.hadd.ps.256", { vector(float,8), vector(float,8) } -> vector(float,8))
terra hadd(v : vector(float,8))
	var v1 = haddavx(v,v)
	var v2 = haddavx(v1,v1)
	return v2[0] + v2[4]
end

local function isinteger(x) return math.floor(x) == x end

function generate(M,N,K,lda,ldb,ldc,AR,BR,KR,V,A,B,C,alpha)
	
	local terra vecload(data : &float, idx : int)
		var addr = &data[idx]
		return @addr:as(&vector(float,V))
	end

	if type(K) == "number" then
		assert(isinteger(K / (KR * V)))
	end
	if type(M) == "number" then
		assert(isinteger(M / AR ))
	end
	if type(N) == "number" then
		assert(isinteger(N / BR ))
	end

	local function mkmatrix(nm,I,J)
		local r = {}
		for i = 0,I-1 do
			r[i] = {}
			for j = 0,J-1 do
				r[i][j] = symbol(nm..tostring(i)..tostring(j))
			end
		end
		return r
	end
	local as,bs,cs = mkmatrix("a",AR,KR),mkmatrix("b",BR,KR),mkmatrix("c",AR,BR)
	local cinits,loopbody,writeback = terralib.newlist(), terralib.newlist(), terralib.newlist()
	local m,n,k = symbol("m"), symbol("n"),symbol("k")
	local alreadyloaded = {}

	for i = 0, AR-1 do
		for j = 0, BR-1 do
			cinits:insert(quote var [cs[i][j]] : vector(float,V) = 0.f end)
		end
	end
		
	local function get(vs,i,j,loadfn)
		if not alreadyloaded[vs[i][j]] then
			alreadyloaded[vs[i][j]] = true
			loopbody:insert(loadfn(vs[i][j]))
		end
		return vs[i][j]
	end

	local function getA(i,j)
		return get(as,i,j,function(sym)
			return quote 
				var [sym] = vecload(A, (m + i) * lda + k + j * V)
			end
		end)
	end

	local function getB(i,j)
		return get(bs,i,j,function(sym)
			return quote
				var [sym] = vecload(B, (n + i) * ldb + k + j * V) 
			end
		end)
	end

	for l = 0, KR-1 do
		for i = 0, AR-1 do
			for j = 0, BR-1 do
				local aa = getA(i,l)
				local bb = getB(j,l)
				loopbody:insert(quote 
					[cs[i][j]] = [cs[i][j]] + aa * bb
				end)
			end
		end
	end

	for i = 0, AR-1 do
		for j = 0, BR-1 do
			local function getsum(b,e)
				if b + 1 == e then
					return `[cs[i][j]][b]
				else
					local mid = (e + b)/2
					assert(math.floor(mid) == mid)
					local lhs = getsum(b,mid)
					local rhs = getsum(mid,e)
					return `lhs + rhs
				end
			end
			local sum
			if V == 8 then
				sum = `hadd([cs[i][j]])
			else
				sum = getsum(0,V)
			end
			writeback:insert(quote
				C[(m + i)*ldc + (n + j)] = alpha*C[(m + i)*ldc + (n + j)] + sum
			end)
		end
	end
	
	local body = quote
		--IO.printf("M %d N %d K %d\n",M,N,K)
		for [m] = 0, M, AR do
			for [n] = 0, N, BR do
				[cinits]
				for [k] = 0, K, V*KR do
					[loopbody]
				end
				[writeback]
			end
		end
	end

	return body
end

function genl1blockmatmul(alpha, M, N, K, AR, BR, KR, V)
	local gen = macro(function(ctx,tree,A,B,C,lda,ldb,ldc)
		return generate(M,N,K,lda,ldb,ldc,AR,BR,KR,V,A,B,C,alpha)
	end)
	local terra impl(A : &float, B : &float, C : &float, lda : int, ldb : int, ldc : int)
		gen(A,B,C,lda,ldb,ldc)
	end
	return impl
end
function genl1matmul(alpha, AR, BR, KR, V)
	local gen = macro(function(ctx,tree,M,N,K,A,B,C,lda,ldb,ldc)
		return generate(M,N,K,lda,ldb,ldc,AR,BR,KR,V,A,B,C,alpha)
	end)
	local terra impl(M : int, N : int, K : int, A : &float, B : &float, C : &float, lda : int, ldb : int, ldc : int)
		gen(M,N,K,A,B,C,lda,ldb,ldc)
	end
	return impl
end


local NB = 72
local NR = 3

local l1blockmatmul0 = genl1blockmatmul(0,NB,NB,NB,NR,NR,NR,8)
local l1blockmatmul1 = genl1blockmatmul(1,NB,NB,NB,NR,NR,NR,8)

local l1matmul0 = genl1matmul(0,2,2,1,8)
local l1matmul1 = genl1matmul(1,2,2,1,8)

l1matmul0:compile()
l1matmul0:printpretty()

terra min(a : int, b : int)
	return terralib.select(a < b,a,b)
end

terra my_sgemm(gettime : {} -> double, M : int, N : int, K : int, alpha : float, A : &float, lda : int, B : &float, ldb : int, 
	           beta : float, C : &float, ldc : int)
	
	var TB = stdlib.malloc(K * N * sizeof(float)):as(&float)
	for kk = 0,K,NB do
		for nn = 0,N,NB do
			for k = kk,min(kk+NB,K) do
				for n = nn,min(nn+NB,N) do
					TB[n*K + k] = B[k*ldb + n]
				end
			end
		end
	end
	B = TB
	ldb = K
	var Krem,Nrem,Mrem = K % NB, N % NB, M % NB
	for mm = 0,M - Mrem,NB do
		for nn = 0, N - Nrem,NB do
			
			for kk = 0, K - Krem, NB do
				if kk == 0 then
					l1blockmatmul0(A + mm*lda + kk,
					               B + nn*ldb + kk,
					               C + mm*ldc + nn,
					               lda,ldb,ldc)
				else
					l1blockmatmul1(A + mm*lda + kk,
					               B + nn*ldb + kk,
					               C + mm*ldc + nn,
					               lda,ldb,ldc)
				end
			end
			
			var kk = K - Krem
			--IO.printf("Krem %d\n",Krem)
		
			l1matmul1(NB,NB,Krem,
			          A + mm*lda + kk,
			          B + nn*ldb + kk,
			          C + mm*ldc + nn,
			          lda,ldb,ldc)
		end
		var Nrem = N % NB
		var nn = N - Nrem
		l1matmul0(NB,Nrem,K,
		          A + mm*lda,
		          B + nn*ldb,
		          C + mm*ldc + nn,
		          lda,ldb,ldc)
	end
	var Mrem = M % NB
	--IO.printf("Mrem %d\n",Mrem)
	var mm = M - Mrem
	l1matmul0(Mrem,N,K,
          A + mm*lda,
          B,
          C + mm*ldc,
          lda,ldb,ldc)


	stdlib.free(B)
end

my_sgemm:compile()
my_sgemm:printpretty()

terralib.saveobj("my_sgemm.o", {my_sgemm = my_sgemm})