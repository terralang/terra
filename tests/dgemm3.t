
function symmat(name,I,...)
	if not I then return symbol(name) end
	local r = {}
	for i = 0,I-1 do
		r[i] = symmat(name..tostring(i),...)
	end
	return r
end


local function isinteger(x) return math.floor(x) == x end

llvmprefetch = terralib.intrinsic("llvm.prefetch",{&uint8,int,int,int} -> {})


function genkernel(NB, RM, RN, V,alpha)

	local A,B,C,mm,nn,ld = symbol("A"),symbol("B"),symbol("C"),symbol("mn"),symbol("nn"),symbol("ld")
	local lda,ldb,ldc = symbol("lda"),symbol("ldb"),symbol("ldc")
	local a,b,c,caddr = symmat("a",RM), symmat("b",RN), symmat("c",RM,RN), symmat("caddr",RM,RN)
	local k = symbol("k")
	
	local loadc,storec = terralib.newlist(),terralib.newlist()

	for m = 0, RM-1 do
		for n = 0, RN-1 do
			loadc:insert(quote
				var [caddr[m][n]] = C + m*ldc + n*V
				var [c[m][n]] = alpha * @[caddr[m][n]]:as(&vector(double,V))
			end)
			storec:insert(quote
				@[caddr[m][n]]:as(&vector(double,V)) = [c[m][n]]
			end)
		end
	end

	local calcc = terralib.newlist()
	
	for n = 0, RN-1 do
		calcc:insert(quote
			var [b[n]] = @(&B[n*V]):as(&vector(double,V))
		end)
	end
	for m = 0, RM-1 do
		calcc:insert(quote
			var [a[m]] = A[m*lda]:as(vector(double,V))
		end)
	end
	for m = 0, RM-1 do 
		for n = 0, RN-1 do
			calcc:insert(quote
				[c[m][n]] = [c[m][n]] + [a[m]] * [b[n]]
			end)
		end
	end
	
	
	return terra([A] : &double, [B] : &double, [C] : &double, [lda] : int64,[ldb] : int64,[ldc] : int64)
		for [mm] = 0, NB, RM do
			for [nn] = 0, NB,RN*V do
				[loadc];
				for [k] = 0, NB do
					llvmprefetch(B + 4*ldb,0,3,1);
					[calcc];
					B = B + ldb
					A = A + 1
				end
				[storec];
				A = A - NB
				B = B - ldb*NB + RN*V
				C = C + RN*V
			end
			C = C + RM * ldb - NB
			B = B - NB
			A = A + lda*RM
		end
	end
end


local stdlib = terralib.includec("stdlib.h")
local IO = terralib.includec("stdio.h")


function generatedgemm(NB,NBF,RM,RN,V)
	
	if not isinteger(NB/(RN*V)) then
		return false
	end
	if not isinteger(NB/RM) then
		return false
	end

	local NB2 = NBF * NB
	local l1dgemm0 = genkernel(NB,RM,RN,V,0)
	local l1dgemm1 = genkernel(NB,RM,RN,V,1)

	local terra min(a : int, b : int)
		return terralib.select(a < b, a, b)
	end

	return terra(gettime : {} -> double, M : int, N : int, K : int, alpha : double, A : &double, lda : int, B : &double, ldb : int, 
		           beta : double, C : &double, ldc : int)
		for mm = 0,M,NB2 do
			for nn = 0,N,NB2 do
				for kk = 0,K, NB2 do
					for m = mm,min(mm+NB2,M),NB do
						for n = nn,min(nn+NB2,N),NB do
							for k = kk,min(kk+NB2,K),NB do
								--IO.printf("%d %d starting at %d\n",m,k,m*lda + NB*k)
								if k == 0 then
									l1dgemm0(A + (m*lda + k),
								         	 B + (k*ldb + n),
								             C + (m*ldc + n),lda,ldb,ldc)
								else
									l1dgemm1(A + (m*lda + k),
								         	 B + (k*ldb + n),
								             C + (m*ldc + n),lda,ldb,ldc)
								end
							end
						end
					end
				end
			end
		end
	end
end

--

local blocksizes = {16,24,32,40,48,56,64}
local regblocks = {1,2,4}
local vectors = {1,2,4,8}

local best = { gflops = 0, b = 56, rm = 4, rn = 1, v = 8 }


if true then
	local tunefor = 1024
	local harness = terralib.require("lib/matrixtestharness")
	for _,b in ipairs(blocksizes) do
		for _,rm in ipairs(regblocks) do
			for _,rn in ipairs(regblocks) do
				for _,v in ipairs(vectors) do
					local my_dgemm = generatedgemm(b,5,rm,rn,v)
					if my_dgemm then
						print(b,rm,rn,v)
						my_dgemm:compile()
						local i = math.floor(tunefor / b) * b
						local avg = 0
						local s, times = harness.timefunctions("double",i,i,i,function(M,K,N,A,B,C)
							my_dgemm(nil,M,N,K,1.0,A,K,B,N,0.0,C,N)
						end)
						if not s then
							print("<error>")
							break
						end
						print(i,unpack(times))
						local avg = times[1]	
						if  best.gflops < avg then
							best = { gflops = avg, b = b, rm = rm, rn = rn, v = v }
							terralib.tree.printraw(best)
						end
					end
				end
			end
		end
	end
end

terralib.tree.printraw(best)

local my_dgemm = generatedgemm(best.b, 5, best.rm, best.rn, best.v)

terralib.saveobj("my_dgemm.o", { my_dgemm = my_dgemm })