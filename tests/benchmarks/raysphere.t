terralib.require("benchmarks/fusion")

terra fill(a : &Array, v : double)
	for i = 0, a.N do
		a.data[i] = v
	end
end

local sqrt = Lift(C.sqrt)

terra main() 

	var n = 10000000;
	var xo : double = 0;
	var yo : double = 0;
	var zo : double = 0;
	var xd : double = 1;
	var yd : double = 0;
	var zd : double = 0;
	
  var xc = Array.new(n);
  var yc = Array.new(n);
  var zc = Array.new(n);
  
	for i = 0,n do
		xc.data[i] = i;
		yc.data[i] = i;
		zc.data[i] = i;
	end

  var b = Array.new(n);
  var c = Array.new(n);
  var disc = Array.new(n);
  var res = Array.new(n);
	fill(&b,0);
	fill(&c,0);
	fill(&disc,0);
	fill(&res,0);

	var begin = C.CurrentTimeInSeconds();

  var a : double = 1;
		
  b:set( 2*(xd*(xo-xc)+yd*(yo-yc)+zd*(zo-zc)) )
  c:set( (xo-xc)*(xo-xc)+(yo-yc)*(yo-yc)+(zo-zc)*(zo-zc)-1 )
  disc:set( b*b-4*c )
  res:set( terralib.select(disc>0, (-b - sqrt(disc))/2,10000000) );
  var r : double = res:min()
	C.printf("%f\n",r);
	C.printf("Elapsed: %f\n", C.CurrentTimeInSeconds()-begin);
	return 0;
end

main()
main:disas()