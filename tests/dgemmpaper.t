
function symmat(typ,name,I,...)
  if not I then return symbol(typ,name) end
  local r = {}
  for i = 0,I-1 do
    r[i] = symmat(typ,name..tostring(i),...)
  end
  return r
end
prefetch = terralib.intrinsic("llvm.prefetch",{&opaque,int,int,int} -> {})


function genkernel(NB, RM, RN, V,alpha)
  local VT = vector(double,V)
  local VP = &VT
  local A,B,C = symbol(VP,"A"),symbol(VP,"B"),symbol(VP,"C")
  local mm,nn = symbol(int,"mn"),symbol(int,"nn")
  local lda,ldb,ldc = symbol(int,"lda"),symbol(int,"ldb"),symbol(int,"ldc")
  local a,b = symmat(VT,"a",RM), symmat(VT,"b",RN)
  local c,caddr = symmat(VT,"c",RM,RN), symmat(VP,"caddr",RM,RN)
  local k = symbol(int,"k")
  local loadc,storec = terralib.newlist(),terralib.newlist()
  for m = 0, RM-1 do for n = 0, RN-1 do
      loadc:insert(quote
        var [caddr[m][n]] = C + m*ldc + n*V
        var [c[m][n]] = 
          alpha * @VP([caddr[m][n]])
      end)
      storec:insert(quote
        @VP([caddr[m][n]]) = [c[m][n]]
      end)
  end end
  local calcc = terralib.newlist()
  for n = 0, RN-1 do
    calcc:insert(quote
      var [b[n]] = @VP(&B[n*V])
    end)
  end
  for m = 0, RM-1 do
    calcc:insert(quote
      var [a[m]] = VT(A[m*lda])
    end)
  end
  for m = 0, RM-1 do for n = 0, RN-1 do
      calcc:insert(quote
        [c[m][n]] = [c[m][n]] + [a[m]] * [b[n]]
      end) 
  end end
  return terra([A] , [B] , [C] ,
               [lda],[ldb] ,[ldc])
    for [mm] = 0, NB, RM do
      for [nn] = 0, NB, RN*V do
        [loadc];
        for [k] = 0, NB do
          prefetch(B + 4*ldb,0,3,1);
          [calcc];
          B,A = B + ldb,A + 1
        end
        [storec];
        A,B,C = A - NB,B - ldb*NB + RN*V,C + RN*V
      end
      A,B,C = A + lda*RM, B - NB, C + RM * ldb - NB
    end
  end
end

local a = genkernel(40,4,2,8,1)
a:compile()
a:printpretty()

terra short_saxpy(a : float, 
      x : vector(float,4), y : vector(float,4))
    return a*x + y
end
short_saxpy:printpretty()