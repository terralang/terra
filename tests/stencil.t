
local C = terralib.includecstring [[
#include<stdio.h>
#include<stdlib.h>
#include <sys/time.h>
static double CurrentTimeInSeconds() {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec + tv.tv_usec / 1000000.0;
}

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


function symmat(name,I,...)
	if not I then return symbol(name) end
	local r = {}
	for i = 0,I-1 do
		r[i] = symmat(name..tostring(i),...)
	end
	return r
end



local IO = terralib.includec("stdio.h")



NI,NJ = 1,1
V = 16

terra uload(d : &float)
	return attribute(@d:as(&vector(float,V)),{align = 4})
end
terra ustore(d : &float, v : vector(float,V))
	attribute(@d:as(&vector(float,V)),{align = 4}) = v
end

terra runit(N : int, input : &float, output : &float)
	for i = NI, N-NI,NI do
		for j = V*NJ, N-V*NJ,V*NJ do
			[(function()
				local C = symmat("C",NI,NJ)
				local stmts = terralib.newlist()
				for iii = 0,NI-1 do for jjj = 0,NJ-1 do 
					stmts:insert(quote 
						var [C[iii][jjj]] : vector(float,V) = 0
					end) 
				end end

				for ii = -1,1 do
					for jj = -1,1 do
						for iii = 0,NI-1 do for jjj = 0,NJ-1 do
							stmts:insert(quote
								var d = uload(input + N * (i + ii + iii) + j + jj + V*jjj);
								[C[iii][jjj]] = [C[iii][jjj]] + d*d
							end)
						end end
					end
				end
				for iii = 0,NI-1 do for jjj = 0,NJ-1 do 
					stmts:insert(quote 
						ustore(output + N * (i + iii) + j + V*jjj, [C[iii][jjj]])
					end) 
				end end
				return stmts
			end)()]
		end
	end
end

terra doit()
	var N = 2048
	var img = C.malloc(N*N*sizeof(float)):as(&float)
	var img2 = C.malloc(N*N*sizeof(float)):as(&float)

	for i = 0, N do
		for j = 0, N do
			img[i*N+j] = 1
		end
	end

	var times  = 0
	var mytime : double
	while C.CalcTime(&times,&mytime) ~= 0 do
		runit(N,img,img2)
	end

	C.printf("times = %d\n",times)
	for i = NI, N-NI do
		for j = V*NJ, N-V*NJ do
			if img2[i*N+j] ~= 9 then
				C.printf("wrong! %d %d %f\n",i,j,img2[i*N+j])
				goto out
			end
		end
	end
	::out::
	var togiga = 1.0/(1024*1024*1024)
	var pixels = (N-NI)*(N-V*NJ)
	C.printf("%f %f %f\n", mytime, pixels*4*2 *togiga / mytime, 18*pixels * togiga / mytime)

end
doit()
runit:disas()
doit()
