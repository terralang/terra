local perf_tests = { benchmark_fannkuchredux = {"10"}, 
                     benchmark_nbody = {"1000000"}, 
                     speed = {} }
                     
local r = terralib.loadfile("perfregression.dat")
r = r and r() or {}

local version = io.popen("git rev-parse --short HEAD"):read("*all")
if #version == 0 then version = "unknown" end

for name,args in pairs(perf_tests) do
    if not r[name] then
        r[name] = {}
    end
    local b = os.clock()
    assert(terralib.loadfile(name..".t"))(unpack(args))
    local e = os.clock()
    local t = e - b
    local c = terralib.llvmversion.."_"..version
    local times = r[name]
    for config,time in pairs(times) do
        if t > time*1.05 then
            error(string.format("perf: regression\nperf: %s:%s: %f\nperf: %s:%s: %f",name,config,time,name,c,t))
        end
    end
    times[c] = t
    print(string.format("perf: recorded: %s:%s: %f",name,c,t))
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