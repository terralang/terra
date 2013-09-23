local C,S = terralib.includecstring [[
	#include <pthread.h>
	#include <sys/time.h>
	#include <signal.h>
	#include <stdio.h>
	#include <string.h>
	#include <stdlib.h>
	#define _XOPEN_SOURCE
	#include <ucontext.h>
    #include <execinfo.h>
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
terra getinfo(ipstr : rawstring, cb : {rawstring,uint64,rawstring,uint64,uint64} -> {}, count: int)
  var ip = @[&&opaque](ipstr)
  var addr : &opaque
  var sz : uint64
  var nm : rawstring, nmL : uint64
  var fname : rawstring, fnameL : uint64
  if terralib.lookupsymbol(ip,&addr,&sz,&nm,&nmL) then
    var offset = [&uint8](ip) - [&uint8](addr)
    C.printf("%p + %d: (%d) %.*s",addr, offset, count, nmL, nm)
    if terralib.lookupline(addr,ip,&fname,&fnameL,&sz) then
        cb(nm,nmL,fname,fnameL,sz)
        C.printf(" (%.*s:%d)",fnameL,fname,int(sz))
    end
    C.printf("\n")
    --terralib.disas(ip,0,1)

  else
    var iparr = array(ip)
    var btstuff = C.backtrace_symbols(iparr, 1)
    C.printf("%p: (%d)    %s\n",ip,count, @btstuff)
    C.free(btstuff)
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
    local typ = &&opaque

    -- Sort the info by sample count
    local sortedcounts = {}
    for k,v in pairs(counts) do
        table.insert(sortedcounts, {key = k, count = v})
    end
    table.sort(sortedcounts, function(a, b) return a.count > b.count end)
    
    local data = {}
    local c
    local function cb(fn,fnL,fl,flL,ln)
        local file = ffi.string(fl,flL)
        ln = tonumber(ln)
        local df = data[file] or {}
        data[file] = df
        df[ln] = (df[ln] or 0) + c
    end
    local typ = &&opaque
    for _,kv in ipairs(sortedcounts) do
        c = kv.count
        getinfo(kv.key, cb, c)
    end
    for file,lines in pairs(data) do
        local i = 1
        local f = io.open(file)
        for l in f:lines() do
            print(lines[i] or 0,l)
            i = i + 1
        end
        f:close()
    end
    C.signal(C.SigProf(),C.SigDfl())
end

return { begin = begin, finish = finish }
