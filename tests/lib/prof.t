local C,S = terralib.includecstring [[
	#include <pthread.h>
	#include <sys/time.h>
	#include <signal.h>
	#include <stdio.h>
	#include <string.h>
	#include <stdlib.h>
	#define _XOPEN_SOURCE
	#include <ucontext.h>
	int SigProf() { return SIGPROF; }
	int SigInfo() { return SA_SIGINFO; }
	int ITimerProf() { return ITIMER_PROF; }
	sig_t SigDfl() { return SIG_DFL; }
unsigned long long CurrentTimeInUSeconds() {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec * 1000000+ tv.tv_usec;
}
]]

local ffi = require("ffi")

struct Samples {
    data : &uint64;
    size : int;
    allocated : int;
}
local samples = terralib.new(Samples)
terra handler(sig : int,  info : &C.siginfo_t, uap : &opaque)
    --C.printf("handler\n")
    var uc = [&C.ucontext_t](uap)
    var rip = uc.uc_mcontext.__ss.__rip;
    if samples.size < samples.allocated then
        samples.data[samples.size] = rip
        samples.size = samples.size + 1
    end
end

terra helperthread(data : &opaque) : &opaque
    var interval = [uint64](data)
    var ts : C.timespec
    ts.tv_sec = interval / 1000000
    ts.tv_nsec = (interval % 1000000) * 1000
    
    while true do
        C.nanosleep(&ts, nil);
        C.kill(0,C.SigProf()) 
    end
    return nil
end 

local starttime
terra printinfo(ip : &opaque, count : int, lines  : &int, fname : rawstring)
  var addr : &opaque
  var sz : uint64
  var nm : int8[128]
  
  if terralib.lookupsymbol(ip,&addr,&sz,nm,128) then 
    C.printf("%p + %d: %s %d\n",addr, [&uint8](ip) - [&uint8](addr), nm,count)
    terralib.disas(ip,0,1)
    if terralib.lookupline(addr,ip,fname,128,&sz) then
        lines[sz] = lines[sz] + count
    end
  else
    C.printf("%p %d\n",addr,count)
  end
end 
local pthread
local function begin(F,N)
    F = F or 1000
    N = N or 1024*1024
    local interval = 1/F * 1000000
    interval = interval * .85 --ad hoc adjustment to get interval to match reality
    samples.size = 0
    samples.allocated = 1024*1024
    samples.data = C.malloc(terralib.sizeof(&opaque)*samples.allocated)
    local sa = terralib.new(S.sigaction)
    sa.sa_flags = C.SigInfo()
    sa.__sigaction_u.__sa_sigaction = handler:getdefinitions()[1]:getpointer()
    assert(0 == C.sigaction(C.SigProf(),sa,nil))
    
    if false then
        local tv = terralib.new(C.itimerval)
        tv.it_interval.tv_sec = 0
        tv.it_interval.tv_usec = 10
        tv.it_value.tv_sec = 0
        tv.it_value.tv_usec = 10
        assert(0 == C.setitimer(C.ITimerProf(),tv,nil))
    else
        local terra startthread()
            var pt : C.pthread_t
            C.pthread_create(&pt,nil,helperthread,[&opaque](int(interval)))
            return pt
        end
        pthread = startthread()
    end    
    starttime = os.clock()
end

local function finish()
    if false then
        local tv = terralib.new(C.itimerval)
        tv.it_interval.tv_sec = 0
        tv.it_interval.tv_usec = 0
        tv.it_value.tv_sec = 0
        tv.it_value.tv_usec = 0
        assert(0 == C.setitimer(C.ITimerProf(),tv,nil))
    else
        C.pthread_cancel(pthread)
    end
    local counts = {}
    local ss = samples.size / (os.clock() - starttime)
    print(samples.size, "samples/second: ", ss )
    for i = 0,samples.size - 1 do
        local k = ffi.string(samples.data + i,8)
        local c = counts[k] or 0
        counts[k] = c + 1
    end
    local lines = terralib.new(int[1024])
    local fname = terralib.new(int8[128])
    local file
    local typ = &&opaque
    for k,v in pairs(counts) do
        local addr = terralib.cast(typ,k)[0]
        printinfo(addr,v,lines,fname)
        file = file or ffi.string(fname)
    end
    local i = 1
    for l in io.open(file):lines() do
        print(lines[i],l)
        i = i + 1
    end
    
    C.signal(C.SigProf(),C.SigDfl())
end

return { begin = begin, finish = finish }
