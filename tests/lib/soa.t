local C = terralib.includec("stdlib.h")
local IO = terralib.includec("stdio.h")

local T = terralib.includecstring [[
#include<stdio.h>
#include<stdlib.h>
#ifndef _WIN32
#include <sys/time.h>
static double CurrentTimeInSeconds() {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec + tv.tv_usec / 1000000.0;
}
#else
#include <time.h>
static double CurrentTimeInSeconds() {
	return time(NULL);
}
#endif

int CalcTime(int * times, double * start) {
	if(*times == 0) {
		*start = CurrentTimeInSeconds();
	} else {
		double elapsed = CurrentTimeInSeconds() - *start;
		if(elapsed > 0.1f && *times >= 3) {
			*start = elapsed / *times;
			return 0;
		}
	}
	(*times)++;
	return 1;
}
]]


function Collection(members,format)
	local collection = terralib.types.newstruct()
	local obj = terralib.types.newstruct()
	local struct Proxy {
		idx : int;
		data : &collection;
	}
	collection.entries:insert { field = "size", type = int }
	if format == "aos" then
		collection.entries:insert { field = "data", type = &obj }
	end

	for k,t in pairs(members) do
		print(k,t)
		if format == "soa" then
			collection.entries:insert{ field = k, type = &t }
			Proxy.methods["get"..k] = terra(self :&Proxy)
				return self.data.[k][self.idx]
			end
			Proxy.methods["set"..k] = terra(self :&Proxy, v : t)
				self.data.[k][self.idx] = v
			end
		else
			obj.entries:insert { field = k, type = t }
			Proxy.methods["get"..k] = terra(self :&Proxy)
				return self.data.data[self.idx].[k]
			end
			Proxy.methods["set"..k] = terra(self :&Proxy, v : t)
				self.data.data[self.idx].[k] = v
			end
		end
	end
	local function initmembers(self,N)
		if format == "soa" then
			local stmts = terralib.newlist()
			for k,t in pairs(members) do
				stmts:insert(quote
					self.[k] = [&t](C.malloc(sizeof(t)*N))
				end)
			end
			return stmts
		else
			return quote
				self.data = [&obj](C.malloc(sizeof(obj)*N))
			end
		end		
	end
	terra collection:init(N : int)
		[ initmembers(self,N) ]
		self.size = N
	end

	terra collection:get(i : int)
		return Proxy { i, self }
	end

	return collection
end

local Obj = Collection( {x = float, y = float, z = float, w = float}, "aos")
local Out = Collection( {x = float }, "aos")


terra foo()
	var a : Obj, oo : Out
	var N = 4096*4096
	a:init(N)
	oo:init(N)
	for i = 0, a.size do
		var o = a:get(i)
		o:setx(i+0)
		o:sety(i+1)
		o:setz(i+2)
		o:setw(i+3)
	end
	var times = 0
	var time = 0.0
	while T.CalcTime(&times,&time) ~= 0 do
	for i = 0, oo.size do
		var r = C.rand() % a.size
		var aa = a:get(r)
		--IO.printf("%d reading %d\n",i,oo.size)
	    var o = oo:get(i)
	    o:setx(aa:getx() + aa:gety() + aa:getz() + aa:getw())
	 end
	 end
	 var r = C.rand() % a.size	 
	 var o = oo:get(r)
	 IO.printf("elapsed %f, %f\n",time,o:getx())
end
--foo()

Mesh = Collection({x = float, y = float, z = float,
                   nx = float, ny = float, nz = float},"aos")

struct Tri {
	a : int;
	b : int;
	c : int;
}

terra main() 
	var file = IO.fopen("/Users/zdevito/Downloads/b1p2.obj","r")
	-- This file is not in the repo
	if file == nil then
		return
	end
	var nv : int, nf : int
	var mesh : Mesh

	IO.fscanf(file,"%d %d\n",&nv,&nf);
	
	mesh:init(nv)
	var tris = [&Tri](C.malloc(sizeof(Tri)*nf))

	for i = 0, nv do
		var x : float,y : float,z : float
		IO.fscanf(file,"v %f %f %f\n",&x,&y,&z)
		var v = mesh:get(i)
		v:setx(x)  v:sety(y)  v:setz(z)
		--v:setx(3*i) v:sety(3*i+1) v:setz(3*i+2)
		v:setnx(0) v:setny(0) v:setnz(0)
		--IO.printf("%f %f %f\n",v:getx(),v:gety(),v:getz())
	end

	for i = 0, nf do
		var a : int, b : int, c : int
		IO.fscanf(file,"f %d %d %d\n",&a,&b,&c)
		tris[i].a = a - 1
		tris[i].b = b - 1
		tris[i].c = c - 1
		--IO.printf("%d %d %d\n",tris[i].a,tris[i].b,tris[i].c)
	end

	var times = 0
	var normalcalc = 0.0

	while T.CalcTime(&times,&normalcalc) ~= 0 do
		for i = 0, nf do 
			--IO.printf("%d %d %d\n",tris[i].a,tris[i].b,tris[i].c)
			var a = mesh:get(tris[i].a)
			var b = mesh:get(tris[i].b)
			var c = mesh:get(tris[i].c)


			var ax,ay,az = a:getx() - c:getx(),a:gety() - c:gety(),a:getz() - c:getz() 
			--IO.printf("%f %f %f\n",ax,ay,az)
			var bx,by,bz = b:getx() - c:getx(),b:gety() - c:gety(),b:getz() - c:getz() 
			
			var nx,ny,nz = ay*bz - az*by,
		                   az*bx - ax*bz,
		                   ax*by - ay*bx
		    
		    a:setnx(a:getnx() + nx)
		    a:setny(a:getny() + ny)
		    a:setnz(a:getnz() + nz)

		    b:setnx(b:getnx() + nx)
		    b:setny(b:getny() + ny)
		    b:setnz(b:getnz() + nz)

		    c:setnx(c:getnx() + nx)
		    c:setny(c:getny() + ny)
		    c:setnz(c:getnz() + nz) 
		end
	end

	var test = mesh:get(1000)
	--IO.printf("%e %e %e\n",test:getnx(),test:getny(),test:getnz())
	var scalecalc = 0.0
	times = 0
	while T.CalcTime(&times,&scalecalc) ~= 0 do
		for i = 0, nv,2 do
			var p = mesh:get(i)
			var p2 = mesh:get(i+1)
			var x1,y1,z1,x2,y2,z2 = p:getx(),p:gety(),p:getz(),
			                        p2:getx(),p2:gety(),p2:getz()
			p:setx(x1 + 12.0)
			p:sety(y1 + 12.0)
			p:setz(z1 + 12.0)
			
			p2:setx(x2 + 12.0)
			p2:sety(y2 + 12.0)
			p2:setz(z2 + 12.0)
			
		end
	end
	var togiga = 1.0/(1024*1024*1024)
	var size = nv*3*4*2
	var nsize = nf*3*4 + nv*3*2*4 + nv*3*4
	IO.printf("%f normal %f translate\n",togiga*nsize/normalcalc,togiga*size/scalecalc)
end

main()


