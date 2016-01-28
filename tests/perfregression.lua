local perf_tests = { benchmark_fannkuchredux = {"10"}, 
                     benchmark_nbody = {"20000000"},
                     benchmark_dgemm = {tostring(3*2048*2048)}
                   }
                     
local r = terralib.loadfile("perfregression.dat")
r = r and r() or {}

local version = io.popen("git rev-parse --short HEAD"):read("*all")
if #version == 0 then version = "unknown\n" end
version = version:sub(1,-2)

local new_runs = {}

for name,args in pairs(perf_tests) do
    local b = terralib.currenttimeinseconds()
    assert(terralib.loadfile(name..".t"))(unpack(args))
    local e = terralib.currenttimeinseconds()
    local t = e - b
    local c = terralib.llvmversion.."_"..version
    local times = r[name]
    new_runs[name] = t
end

local regression_occured = false
print()
for name,args in pairs(perf_tests) do
    if not r[name] then
        r[name] = {}
    end
    local t = new_runs[name]
    local c = terralib.llvmversion.."_"..version
    local times = r[name]
    
    local regression = false
    for config,time in pairs(times) do
        if t > time*1.05 then
            regression,regression_occured = true,true
        end
        print(string.format("%s:%s: %f",name,config,time))
    end
    print(string.format("%s:%s: %f%s",name,c,t,regression and "!!!!!" or ""))
    print()
    times[c] = t
end
if regression_occured then
    error("regressions occured")
end

local function write(f,obj)
    if type(obj) ~= "table" then 
        f:write(tostring(obj)) 
        return
    end
    f:write("{")
    for k,v in pairs(obj) do
        f:write(string.format("[%q] = ",k))
        write(f,v)
        f:write(";")
    end
    f:write("}")
end

local F = io.open("perfregression.dat","w")
F:write("return ")
write(F,r)
F:close()