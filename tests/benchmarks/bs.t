

terralib.require("benchmarks/fusion")



N_OPTIONS = 10000000;
N_BLACK_SCHOLES_ROUNDS = 1
invSqrt2Pi = 0.39894228040
LOG10 = math.log(10);

--[[
double cnd(double X) {	
	double k = 1.0 / (1.0 + 0.2316419 * fabs(X)); 
	double w = (((((1.330274429*k) - 1.821255978)*k + 1.781477937)*k - 0.356563782)*k + 0.31938153)*k;
	w = w * invSqrt2Pi * exp(X * X * -.5);
	if(X > 0) return 1.0-w;
	else return w;
}
]]

trans = false
if trans then
	sqrt = Lift(C.sqrt)
	log = Lift(C.log)
	fabs = Lift(C.fabs)
	exp = Lift(C.exp)
else
	local id = macro(function(exp) return exp end)
	sqrt = id --Lift(C.sqrt)
	log = id --Lift(C.log)
	fabs = id --Lift(C.fabs)
	exp = id --Lift(C.exp)
end


terra cnd(a : &Array, X : &Array, k : &Array, w : &Array)
	k:set(1 / (1.0 + 0.2316419 * fabs(@X)))
	w:set((((((1.330274429*@k) - 1.821255978)*@k + 1.781477937)*@k - 0.356563782)*@k + 0.31938153)*@k)
	w:set(@w * invSqrt2Pi * exp(@X * @X * -0.5))
	a:set( terralib.select(@X > 0, 1.0 - @w, @w) )
end

terra fill(a : &Array, v : double)
	for i = 0, a.N do
		a.data[i] = v
	end
end



terra main()
	var S,X,TT,r,v = Array.new(N_OPTIONS),Array.new(N_OPTIONS),Array.new(N_OPTIONS),Array.new(N_OPTIONS),Array.new(N_OPTIONS)
	fill(&S,100.0)
	fill(&X,98.0)
	fill(&TT,2.0)
	fill(&r,.02)
	fill(&v,5.0)

	var delta,d1,d2,cnd1,cnd2,k,w = Array.new(N_OPTIONS),Array.new(N_OPTIONS),Array.new(N_OPTIONS),Array.new(N_OPTIONS),Array.new(N_OPTIONS),Array.new(N_OPTIONS),Array.new(N_OPTIONS)
	fill(&delta,0)
	fill(&d1,0)
	fill(&d2,0)
	fill(&cnd1,0)
	fill(&cnd2,0)
	fill(&k,0)
	fill(&w,0)
	
	var acc = Array.new(N_OPTIONS)
	fill(&acc,0)
	
	var begin = C.CurrentTimeInSeconds();
	--[[
	for(int j = 0; j < N_BLACK_SCHOLES_ROUNDS; j++) {

		delta = v * TT.sqrt();
			
		for(int i = 0; i < N_OPTIONS; i++) {
			double delta = v[i] * sqrt(TT[i]);
			double d1 = (log(S[i]/X[i])/LOG10 + (r[i] + v[i] * v[i] * .5) * TT[i]) / delta;
			double d2 = d1 - delta;
			acc += S[i] * cnd(d1) - X[i] * exp(-r[i] * TT[i]) * cnd(d2);
		}

	}]]
	var result = 0.0
	for j = 0,N_BLACK_SCHOLES_ROUNDS do
		delta:set(v * sqrt(TT))
		d1:set( (log(S/X)/LOG10 + (r + v * v * 0.5) * TT) / delta )
		d2:set( d1 - delta )
		cnd(&cnd1,&d1,&k,&w)
		cnd(&cnd2,&d2,&k,&w)
		acc:set(S * cnd1 - X * exp(-r*TT) * cnd2)
		result = result + acc:sum()
	end
	result = result / (N_BLACK_SCHOLES_ROUNDS * N_OPTIONS) 
	C.printf("Elapsed: %f\n",C.CurrentTimeInSeconds() - begin);
	C.printf("%f\n",result);
end

main:disas()
main()