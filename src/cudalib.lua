-- See Copyright Notice in ../LICENSE.txt

cudalib = {}

function terralib.cudacompile(...)
    return cudalib.compile(...)
end

local ffi = require('ffi')

local cudaruntimelinked = false
function cudalib.linkruntime(cudahome)
    if cudaruntimelinked then return end
    terralib.linklibrary(terralib.cudalibpaths.driver)
    terralib.linklibrary(terralib.cudalibpaths.runtime)
    cudaruntimelinked = true
end

terralib.CUDAParams = terralib.types.newstruct("CUDAParams")
terralib.CUDAParams.entries = { { "gridDimX", uint },
                                { "gridDimY", uint },
                                { "gridDimZ", uint },
                                { "blockDimX", uint },
                                { "blockDimY", uint },
                                { "blockDimZ", uint },
                                { "sharedMemBytes", uint },
                                {"hStream" , terra.types.pointer(opaque) } }
                                
function cudalib.toptx(module,dumpmodule,version)
    dumpmodule,version = not not dumpmodule,assert(tonumber(version))
    local cu = terralib.newcompilationunit(terra.cudatarget, false) -- TODO: add nvptx target options here
    local annotations = terra.newlist{} -- list of annotations { functionname, annotationname, annotationvalue } to be tagged
    local function addkernel(k,fn)
        fn:setinlined(true)
        
        local typ = fn:gettype()
        if not typ.returntype:isunit() then
            error(k..": kernels must return no arguments.")
        end

        for _,p in ipairs(typ.parameters) do
            if p:isarray() or p:isstruct() then -- we can't pass aggregates by value through CUDA, so wrap/unwrap the kernel
                fn = cudalib.flattenkernel(fn)
                break
            end
        end
        cu:addvalue(k,fn)
        annotations:insert({k,"kernel",1})
    end
    
    for k,v in pairs(module) do
        k = tostring(k)
        if not k:match("[%w_]+") then
            error("cuda symbol names must be valid identifiers, but found: "..k)
        end
        if terra.isfunction(v) then
            addkernel(k,v)
        elseif type(v) == "table" and terra.isfunction(v.kernel) then -- annotated kernel
            addkernel(k,v.kernel)
            if v.annotations then
                for i,a in pairs(v.annotations) do
                    annotations:insert({k,tostring(a[1]),tonumber(a[2])})
                end
            end
        else
            if cudalib.isconstant(v) then
                v = v.global
            end
            if terralib.isglobalvar(v) then
                cu:addvalue(k,v)
            else
                error("module must contain only terra functions, globals, or cuda constants")
            end
        end
    end

    -- Find libdevice module
    local libdevice
    local libdevice_version
    local dir = terra.cudahome..(ffi.os == 'Windows' and '\\nvvm\\libdevice' or '/nvvm/libdevice')
    local cmd = ffi.os == 'Windows' and 'dir "'..dir..'" /b' or 'ls "'..dir..'"'
    local pfile = io.popen(cmd)
    for fname in pfile:lines() do
        if fname:match('^libdevice%.10%.bc$') then
            libdevice = dir..(ffi.os == 'Windows' and '\\' or '/')..fname
            break
        end
        local x, y = fname:match('^libdevice%.compute_([0-9])([0-9])%.10%.bc$')
        if x and y then
            local v = 10 * x + y
            if v <= version and (not libdevice or v > libdevice_version) then
                libdevice = dir..(ffi.os == 'Windows' and '\\' or '/')..fname
                libdevice_version = v
            end
        end
    end
    pfile:close()

    --call into tcuda.cpp to perform compilation
    local r = terralib.toptximpl(cu,annotations,dumpmodule,version,libdevice)
    cu:free()
    return r
end

cudalib.useculink = false

-- we need to use terra to write the function that JITs the right wrapper functions forCUDA kernels
-- since this file is loaded as Lua, we use terra.loadstring to inject some terra code
-- this this is only needed for cuda compilation, we load this library lazily below
local terracode = [[
local ffi = require('ffi')
local ef = terralib.externfunction
local struct CUctx_st
local struct CUfunc_st
local struct CUlinkState_st
local struct CUmod_st
local snprintf = ffi.os == "Windows" and "_snprintf" or "snprintf"
-- import all CUDA state that we need, we avoid includec because it is slow
local C = {
    CU_JIT_ERROR_LOG_BUFFER = 5;
    CU_JIT_ERROR_LOG_BUFFER_SIZE_BYTES = 6;
    CU_JIT_INPUT_PTX = 1;
    CU_JIT_TARGET = 9;
    CUcontext = &CUctx_st;
    CUdevice = int32;
    CUdeviceptr = uint64;
    CUfunction = &CUfunc_st;
    CUjit_option = uint32;
    
    cuCtxCreate_v2 = ef("cuCtxCreate_v2",{&&CUctx_st,uint32,int32} -> uint32);
    cuCtxGetCurrent = ef("cuCtxGetCurrent",{&&CUctx_st} -> uint32);
    cuCtxGetDevice = ef("cuCtxGetDevice",{&int32} -> uint32);
    cuDeviceComputeCapability = ef("cuDeviceComputeCapability",{&int32,&int32,int32} -> uint32);
    cuDeviceGet = ef("cuDeviceGet",{&int32,int32} -> uint32);
    cuInit = ef("cuInit",{uint32} -> uint32);
    cuLaunchKernel = ef("cuLaunchKernel",{&CUfunc_st,uint32,uint32,uint32,uint32,uint32,uint32,uint32,&opaque,&&opaque,&&opaque} -> uint32);
    cuLinkAddData_v2 = ef("cuLinkAddData_v2",{&CUlinkState_st,uint32,&opaque,uint64,&int8,uint32,&uint32,&&opaque} -> uint32);
    cuLinkComplete = ef("cuLinkComplete",{&CUlinkState_st,&&opaque,&uint64} -> uint32);
    cuLinkCreate_v2 = ef("cuLinkCreate_v2",{uint32,&uint32,&&opaque,&&CUlinkState_st} -> uint32);
    cuLinkDestroy = ef("cuLinkDestroy",{&CUlinkState_st} -> uint32);
    CUlinkState = &CUlinkState_st;
    CUmodule = &CUmod_st;
    cuModuleGetFunction = ef("cuModuleGetFunction",{&&CUfunc_st,&CUmod_st,&int8} -> uint32);
    cuModuleGetGlobal_v2 = ef("cuModuleGetGlobal_v2",{&uint64,&uint64,&CUmod_st,&int8} -> uint32);
    cuModuleLoadData = ef("cuModuleLoadData",{&&CUmod_st,&opaque} -> uint32);
    cuFuncGetAttribute = ef("cuFuncGetAttribute", {&int,int,&CUfunc_st} -> uint32);
    cuGetErrorString = ef("cuGetErrorString", {uint32,&rawstring} -> uint32);
    exit = ef("exit",{int32} -> {});
    printf = ef("printf",terralib.types.funcpointer(&int8,int32,true));
    snprintf = ef(snprintf,terralib.types.funcpointer({&int8,uint64,&int8},int32,true));
    strlen = ef("strlen",{&int8} -> uint64);
}

local function unwrapexpressions(paramtypes) -- helper that gets around calling convension issues by unwrapping aggregates
                                             -- for kernel invocations
    local flatsymbols, expressions = terralib.newlist(),terralib.newlist()
    local function addtype(s,t)
        if t:isstruct() then
            for i,e in ipairs(t:getentries()) do
                if not e.type then 
                    error("cuda kernels cannot pass struct "..tostring(t).." by value because it contains a union")
                end
                addtype(`s.[e.field],e.type)
            end
        elseif t:isarray() then
            for i = 0,t.N - 1 do
                addtype(`s[i],t.type)
            end
        else
            flatsymbols:insert(terralib.newsymbol(t))
            expressions:insert(s)
        end
    end
    local symbols = paramtypes:map(terralib.newsymbol)
    for i,s in ipairs(symbols) do
        addtype(s,paramtypes[i])
    end
    return symbols,flatsymbols,expressions 
end
function cudalib.flattenkernel(v)
    local symbols,flatsymbols,expressions = unwrapexpressions(v:gettype().parameters)
    return terra([flatsymbols])
        var [symbols]
        expressions = flatsymbols
        return v(symbols)
    end
end

local function makekernelwrapper(typ,name,fnhandle)
    local symbols,flatsymbols,expressions = unwrapexpressions(typ.parameters)
    local paramctor = flatsymbols:map(function(s) return `&s end)
    return terra(params : &terralib.CUDAParams, [symbols])
        if fnhandle == nil then
            C.printf("cuda kernel %s compiled from terra was not initialized.\n",name);
            C.exit(1);
        end
        var [flatsymbols] = expressions
        var paramlist = arrayof([&opaque],[paramctor])
        return C.cuLaunchKernel(fnhandle,params.gridDimX,params.gridDimY,params.gridDimZ,
                                      params.blockDimX,params.blockDimY,params.blockDimZ,
                                      params.sharedMemBytes, params.hStream,paramlist,nil)
    end
end

local error_str = symbol(rawstring)
local error_sz = symbol(uint64)
local cd = macro(function(nm,...)
    local args = {...}
    nm = nm:asvalue()
    local fn = assert(C[nm])
    return quote
        var r = fn(args)
        if r ~= 0 then
            if error_str ~= nil then
                var start = C.strlen(error_str)
                if error_sz - start > 0 then
                    var s : rawstring
                    C.cuGetErrorString(r, &s)
                    C.snprintf(error_str+start,error_sz - start,"%s: cuda reported error %d: %s",nm,r,s)
                end
            end
            return r
        end
    end
end)
local terra initcuda(CX : &C.CUcontext, D : &C.CUdevice, version : &uint64, 
                    [error_str], [error_sz])
    if error_sz > 0 then error_str[0] = 0 end
    cd("cuInit",0)
    cd("cuCtxGetCurrent",CX)
    if @CX ~= nil then
        -- there is already a valid cuda context, so use that
        cd("cuCtxGetDevice",D)
    else
        cd("cuDeviceGet",D,0)
        cd("cuCtxCreate_v2",CX,0,@D)
    end
    var major : int, minor : int
    cd("cuDeviceComputeCapability",&major,&minor,@D)
    @version = major * 10 + minor
    return 0
end

local error_buf_sz = 2048
local error_buf = terralib.new(int8[error_buf_sz])
function cudalib.localversion()
    cudalib.linkruntime()
    local S = terralib.new(tuple(C.CUcontext[1],C.CUdevice[1],uint64[1]))
    if initcuda(S._0,S._1,S._2,error_buf,error_buf_sz) ~= 0 then
        error(ffi.string(error_buf))
    end
    return tonumber(S._2[0])
end

local return1 = macro(function(x)
    return quote
        var r = x;
        if r ~= 0 then return r end
    end
end)


local terra loadmodule(cudaM : &C.CUmodule, ptx : rawstring, ptx_sz : uint64,
                       useculink : bool, linker : {C.CUlinkState,rawstring,uint64} -> int,
                       module : {&opaque,uint64} -> {},
                       [error_str],[error_sz])
    if error_sz > 0 then error_str[0] = 0 end
    var D : C.CUdevice
    var CX : C.CUcontext
    var version : uint64
    
    return1(initcuda(&CX,&D,&version,error_str,error_sz))
    
    if useculink or linker ~= nil then
        var linkState : C.CUlinkState
        var cubin : &opaque
        var cubinSize : uint64

        var options = arrayof(C.CUjit_option,C.CU_JIT_TARGET, C.CU_JIT_ERROR_LOG_BUFFER,C.CU_JIT_ERROR_LOG_BUFFER_SIZE_BYTES)
        var option_values = arrayof([&opaque], [&opaque](version), error_str, [&opaque](error_sz));


        cd("cuLinkCreate_v2",terralib.select(error_str == nil,1,3),options,option_values,&linkState)
        cd("cuLinkAddData_v2",linkState,C.CU_JIT_INPUT_PTX,ptx,ptx_sz,nil,0,nil,nil)

        if linker ~= nil then
            return1(linker(linkState,error_str,error_sz))
        end
        
        cd("cuLinkComplete",linkState,&cubin,&cubinSize)

        if module ~= nil then
            module(cubin,cubinSize)
        end
        cd("cuModuleLoadData",cudaM, cubin)
        cd("cuLinkDestroy",linkState)
    else
        cd("cuModuleLoadData",cudaM, ptx)
    end
end

function cudalib.wrapptx(module,ptx)
    local ptxc = terralib.constant(ptx)
    local m = {}
    local fnhandles = {}
    local terra loader(linker : {C.CUlinkState,rawstring,uint64} -> int,
                       module_fn : {&opaque,uint64} -> {},
                       [error_str],[error_sz])
        if error_sz > 0 then error_str[0] = 0 end
        var cudaM : C.CUmodule
        return1(loadmodule(&cudaM,ptxc,[ptx:len() + 1],cudalib.useculink,linker,module_fn,error_str,error_sz))
        escape
            for k,v in pairs(module) do
                
                if type(v) == "table" and terralib.isfunction(v.kernel) then
                    v = v.kernel
                end
                if terralib.isfunction(v) then
                    local gbl = global(`C.CUfunction(nil))
                    fnhandles[k] = gbl
                    m[k] = makekernelwrapper(v:gettype(),k,gbl)
                    emit quote
                        cd("cuModuleGetFunction",[&C.CUfunction](&gbl),cudaM,k)
                    end
                elseif cudalib.isconstant(v) or terralib.isglobalvar(v) then
                    local gbl = global(`[&opaque](nil))
                    m[k] = gbl
                    emit quote
                        var bytes : uint64
                        cd("cuModuleGetGlobal_v2",[&C.CUdeviceptr](&gbl),&bytes,cudaM,k)
                    end
                else
                    error("unexpected entry in table of type: "..type(v),3)
                end
            end
        end
        return 0
    end
    return m,loader,fnhandles
end

local function dumpsass(data,sz)
    local data = ffi.string(data,sz)
    local f = io.open("dump.sass","wb")
    f:write(data)
    f:close()
    local nvdisasm = terralib.cudahome..(ffi.os == "Windows" and "\\bin\\nvdisasm.exe" or "/bin/nvdisasm")
    os.execute(string.format("%q --print-life-ranges dump.sass",nvdisasm))
end
dumpsass = terralib.cast({&opaque,uint64} -> {},dumpsass)

function cudalib.compile(module,dumpmodule,version,jitload)
    version = version or cudalib.localversion()
    if jitload == nil then jitload = true end
    local ptx = cudalib.toptx(module,dumpmodule,version)
    local m,loader,fnhandles = cudalib.wrapptx(module,ptx,dumpmodule)
    if jitload then
        cudalib.linkruntime()
        if 0 ~= loader(nil,dumpmodule and dumpsass or nil,error_buf,error_buf_sz) then
            error(ffi.string(error_buf),2)
        end
    end
    return m,loader,fnhandles
end

function cudalib.sharedmemory(typ,N)
    local gv = terralib.global(typ[N],nil,nil,N == 0,false,3)
    return `[&typ](cudalib.nvvm_ptr_shared_to_gen_p0i8_p3i8([terralib.types.pointer(typ,3)](&gv[0])))
end
local constant = {
    __toterraexpression = function(self)
        return `[&self.type](cudalib.nvvm_ptr_constant_to_gen_p0i8_p4i8([terralib.types.pointer(self.type,4)](&[self.global][0])))
    end
}
function cudalib.isconstant(c)
    return getmetatable(c) == constant
end
function cudalib.constantmemory(typ,N)
    local c = { type = typ, global = terralib.global(typ[N],nil,nil,false,false,4) }
    return setmetatable(c,constant)
end
]]

local builtintablestring = [[
return {
    nvvm_ceil_d =  double -> double;
    nvvm_ex2_approx_d =  double -> double;
    nvvm_fabs_d =  double -> double;
    nvvm_floor_d =  double -> double;
    nvvm_lg2_approx_d =  double -> double;
    nvvm_rcp_approx_ftz_d =  double -> double;
    nvvm_rcp_rm_d =  double -> double;
    nvvm_rcp_rn_d =  double -> double;
    nvvm_rcp_rp_d =  double -> double;
    nvvm_rcp_rz_d =  double -> double;
    nvvm_round_d =  double -> double;
    nvvm_rsqrt_approx_d =  double -> double;
    nvvm_saturate_d =  double -> double;
    nvvm_sqrt_rm_d =  double -> double;
    nvvm_sqrt_rn_d =  double -> double;
    nvvm_sqrt_rp_d =  double -> double;
    nvvm_sqrt_rz_d =  double -> double;
    nvvm_trunc_d =  double -> double;
    nvvm_add_rm_d =  {double,double} -> double;
    nvvm_add_rn_d =  {double,double} -> double;
    nvvm_add_rp_d =  {double,double} -> double;
    nvvm_add_rz_d =  {double,double} -> double;
    nvvm_div_rm_d =  {double,double} -> double;
    nvvm_div_rn_d =  {double,double} -> double;
    nvvm_div_rp_d =  {double,double} -> double;
    nvvm_div_rz_d =  {double,double} -> double;
    nvvm_fmax_d =  {double,double} -> double;
    nvvm_fmin_d =  {double,double} -> double;
    nvvm_mul_rm_d =  {double,double} -> double;
    nvvm_mul_rn_d =  {double,double} -> double;
    nvvm_mul_rp_d =  {double,double} -> double;
    nvvm_mul_rz_d =  {double,double} -> double;
    nvvm_fma_rm_d =  {double,double,double} -> double;
    nvvm_fma_rn_d =  {double,double,double} -> double;
    nvvm_fma_rp_d =  {double,double,double} -> double;
    nvvm_fma_rz_d =  {double,double,double} -> double;
    nvvm_i2d_rm =  int -> double;
    nvvm_i2d_rn =  int -> double;
    nvvm_i2d_rp =  int -> double;
    nvvm_i2d_rz =  int -> double;
    nvvm_lohi_i2d =  {int,int} -> double;
    nvvm_bitcast_ll2d =  int64 -> double;
    nvvm_ll2d_rm =  int64 -> double;
    nvvm_ll2d_rn =  int64 -> double;
    nvvm_ll2d_rp =  int64 -> double;
    nvvm_ll2d_rz =  int64 -> double;
    nvvm_ui2d_rm =  uint -> double;
    nvvm_ui2d_rn =  uint -> double;
    nvvm_ui2d_rp =  uint -> double;
    nvvm_ui2d_rz =  uint -> double;
    nvvm_ull2d_rm =  uint64 -> double;
    nvvm_ull2d_rn =  uint64 -> double;
    nvvm_ull2d_rp =  uint64 -> double;
    nvvm_ull2d_rz =  uint64 -> double;
    nvvm_d2f_rm =  float -> double;
    nvvm_d2f_rm_ftz =  float -> double;
    nvvm_d2f_rn =  float -> double;
    nvvm_d2f_rn_ftz =  float -> double;
    nvvm_d2f_rp =  float -> double;
    nvvm_d2f_rp_ftz =  float -> double;
    nvvm_d2f_rz =  float -> double;
    nvvm_d2f_rz_ftz =  float -> double;
    nvvm_ceil_f =  float -> float;
    nvvm_ceil_ftz_f =  float -> float;
    nvvm_cos_approx_f =  float -> float;
    nvvm_cos_approx_ftz_f =  float -> float;
    nvvm_ex2_approx_f =  float -> float;
    nvvm_ex2_approx_ftz_f =  float -> float;
    nvvm_fabs_f =  float -> float;
    nvvm_fabs_ftz_f =  float -> float;
    nvvm_floor_f =  float -> float;
    nvvm_floor_ftz_f =  float -> float;
    nvvm_lg2_approx_f =  float -> float;
    nvvm_lg2_approx_ftz_f =  float -> float;
    nvvm_rcp_rm_f =  float -> float;
    nvvm_rcp_rm_ftz_f =  float -> float;
    nvvm_rcp_rn_f =  float -> float;
    nvvm_rcp_rn_ftz_f =  float -> float;
    nvvm_rcp_rp_f =  float -> float;
    nvvm_rcp_rp_ftz_f =  float -> float;
    nvvm_rcp_rz_f =  float -> float;
    nvvm_rcp_rz_ftz_f =  float -> float;
    nvvm_round_f =  float -> float;
    nvvm_round_ftz_f =  float -> float;
    nvvm_rsqrt_approx_f =  float -> float;
    nvvm_rsqrt_approx_ftz_f =  float -> float;
    nvvm_saturate_f =  float -> float;
    nvvm_saturate_ftz_f =  float -> float;
    nvvm_sin_approx_f =  float -> float;
    nvvm_sin_approx_ftz_f =  float -> float;
    nvvm_sqrt_approx_f =  float -> float;
    nvvm_sqrt_approx_ftz_f =  float -> float;
    nvvm_sqrt_rm_f =  float -> float;
    nvvm_sqrt_rm_ftz_f =  float -> float;
    nvvm_sqrt_rn_f =  float -> float;
    nvvm_sqrt_rn_ftz_f =  float -> float;
    nvvm_sqrt_rp_f =  float -> float;
    nvvm_sqrt_rp_ftz_f =  float -> float;
    nvvm_sqrt_rz_f =  float -> float;
    nvvm_sqrt_rz_ftz_f =  float -> float;
    nvvm_trunc_f =  float -> float;
    nvvm_trunc_ftz_f =  float -> float;
    nvvm_add_rm_f =  {float,float} -> float;
    nvvm_add_rm_ftz_f =  {float,float} -> float;
    nvvm_add_rn_f =  {float,float} -> float;
    nvvm_add_rn_ftz_f =  {float,float} -> float;
    nvvm_add_rp_f =  {float,float} -> float;
    nvvm_add_rp_ftz_f =  {float,float} -> float;
    nvvm_add_rz_f =  {float,float} -> float;
    nvvm_add_rz_ftz_f =  {float,float} -> float;
    nvvm_div_approx_f =  {float,float} -> float;
    nvvm_div_approx_f =  {float,float} -> float;
    nvvm_div_approx_ftz_f =  {float,float} -> float;
    nvvm_div_rm_f =  {float,float} -> float;
    nvvm_div_rm_ftz_f =  {float,float} -> float;
    nvvm_div_rn_f =  {float,float} -> float;
    nvvm_div_rn_ftz_f =  {float,float} -> float;
    nvvm_div_rp_f =  {float,float} -> float;
    nvvm_div_rp_ftz_f =  {float,float} -> float;
    nvvm_div_rz_f =  {float,float} -> float;
    nvvm_div_rz_ftz_f =  {float,float} -> float;
    nvvm_fmax_f =  {float,float} -> float;
    nvvm_fmax_ftz_f =  {float,float} -> float;
    nvvm_fmin_f =  {float,float} -> float;
    nvvm_fmin_ftz_f =  {float,float} -> float;
    nvvm_mul_rm_f =  {float,float} -> float;
    nvvm_mul_rm_ftz_f =  {float,float} -> float;
    nvvm_mul_rn_f =  {float,float} -> float;
    nvvm_mul_rn_ftz_f =  {float,float} -> float;
    nvvm_mul_rp_f =  {float,float} -> float;
    nvvm_mul_rp_ftz_f =  {float,float} -> float;
    nvvm_mul_rz_f =  {float,float} -> float;
    nvvm_mul_rz_ftz_f =  {float,float} -> float;
    nvvm_fma_rm_f =  {float,float,float} -> float;
    nvvm_fma_rm_ftz_f =  {float,float,float} -> float;
    nvvm_fma_rn_f =  {float,float,float} -> float;
    nvvm_fma_rn_ftz_f =  {float,float,float} -> float;
    nvvm_fma_rp_f =  {float,float,float} -> float;
    nvvm_fma_rp_ftz_f =  {float,float,float} -> float;
    nvvm_fma_rz_f =  {float,float,float} -> float;
    nvvm_fma_rz_ftz_f =  {float,float,float} -> float;
    nvvm_bitcast_i2f =  int -> float;
    nvvm_i2f_rm =  int -> float;
    nvvm_i2f_rn =  int -> float;
    nvvm_i2f_rp =  int -> float;
    nvvm_i2f_rz =  int -> float;
    nvvm_ll2f_rm =  int64 -> float;
    nvvm_ll2f_rn =  int64 -> float;
    nvvm_ll2f_rp =  int64 -> float;
    nvvm_ll2f_rz =  int64 -> float;
    nvvm_ui2f_rm =  uint -> float;
    nvvm_ui2f_rn =  uint -> float;
    nvvm_ui2f_rp =  uint -> float;
    nvvm_ui2f_rz =  uint -> float;
    nvvm_ull2f_rm =  uint64 -> float;
    nvvm_ull2f_rn =  uint64 -> float;
    nvvm_ull2f_rp =  uint64 -> float;
    nvvm_ull2f_rz =  uint64 -> float;
    nvvm_h2f =  uint16 -> float;
    nvvm_read_ptx_sreg_ctaid_x =  {} -> int;
    nvvm_read_ptx_sreg_ctaid_y =  {} -> int;
    nvvm_read_ptx_sreg_ctaid_z =  {} -> int;
    nvvm_read_ptx_sreg_nctaid_x =  {} -> int;
    nvvm_read_ptx_sreg_nctaid_y =  {} -> int;
    nvvm_read_ptx_sreg_nctaid_z =  {} -> int;
    nvvm_read_ptx_sreg_ntid_x =  {} -> int;
    nvvm_read_ptx_sreg_ntid_y =  {} -> int;
    nvvm_read_ptx_sreg_ntid_z =  {} -> int;
    nvvm_read_ptx_sreg_tid_x =  {} -> int;
    nvvm_read_ptx_sreg_tid_y =  {} -> int;
    nvvm_read_ptx_sreg_tid_z =  {} -> int;
    nvvm_read_ptx_sreg_warpsize =  {} -> int;
    ptx_read_clock =  {} -> int;
    ptx_read_gridid =  {} -> int;
    ptx_read_laneid =  {} -> int;
    ptx_read_lanemask_eq =  {} -> int;
    ptx_read_lanemask_ge =  {} -> int;
    ptx_read_lanemask_gt =  {} -> int;
    ptx_read_lanemask_le =  {} -> int;
    ptx_read_lanemask_lt =  {} -> int;
    ptx_read_nsmid =  {} -> int;
    ptx_read_nwarpid =  {} -> int;
    ptx_read_pm0 =  {} -> int;
    ptx_read_pm1 =  {} -> int;
    ptx_read_pm2 =  {} -> int;
    ptx_read_pm3 =  {} -> int;
    ptx_read_smid =  {} -> int;
    ptx_read_warpid =  {} -> int;
    nvvm_d2i_hi =  double -> int;
    nvvm_d2i_lo =  double -> int;
    nvvm_d2i_rm =  double -> int;
    nvvm_d2i_rn =  double -> int;
    nvvm_d2i_rp =  double -> int;
    nvvm_d2i_rz =  double -> int;
    nvvm_bitcast_f2i =  float -> int;
    nvvm_f2i_rm =  float -> int;
    nvvm_f2i_rm_ftz =  float -> int;
    nvvm_f2i_rn =  float -> int;
    nvvm_f2i_rn_ftz =  float -> int;
    nvvm_f2i_rp =  float -> int;
    nvvm_f2i_rp_ftz =  float -> int;
    nvvm_f2i_rz =  float -> int;
    nvvm_f2i_rz_ftz =  float -> int;
    nvvm_abs_i =  int -> int;
    nvvm_barrier0_and =  int -> int;
    nvvm_barrier0_or =  int -> int;
    nvvm_barrier0_popc =  int -> int;
    nvvm_clz_i =  int -> int;
    nvvm_popc_i =  int -> int;
    nvvm_max_i =  {int,int} -> int;
    nvvm_min_i =  {int,int} -> int;
    nvvm_mul24_i =  {int,int} -> int;
    nvvm_mulhi_i =  {int,int} -> int;
    nvvm_sad_i =  {int,int,int} -> int;
    nvvm_clz_ll =  int64 -> int;
    ptx_read_clock64 =  {} -> int64;
    nvvm_abs_ll =  int64 ->int64;
    nvvm_popc_ll =  int64 ->int64;
    nvvm_bitcast_d2ll =  double ->int64;
    nvvm_d2ll_rm =  double ->int64;
    nvvm_d2ll_rn =  double ->int64;
    nvvm_d2ll_rp =  double ->int64;
    nvvm_d2ll_rz =  double ->int64;
    nvvm_f2ll_rm =  float -> int64;
    nvvm_f2ll_rm_ftz =  float -> int64;
    nvvm_f2ll_rn =  float -> int64;
    nvvm_f2ll_rn_ftz =  float -> int64;
    nvvm_f2ll_rp =  float -> int64;
    nvvm_f2ll_rp_ftz =  float -> int64;
    nvvm_f2ll_rz =  float -> int64;
    nvvm_f2ll_rz_ftz =  float -> int64;
    nvvm_max_ll =  {int64,int64} -> int64;
    nvvm_min_ll =  {int64,int64} -> int64;
    nvvm_mulhi_ll =  {int64,int64} -> int64;
    nvvm_d2ui_rm =  double -> uint;
    nvvm_d2ui_rn =  double -> uint;
    nvvm_d2ui_rp =  double -> uint;
    nvvm_d2ui_rz =  double -> uint;
    nvvm_f2ui_rm =  float -> uint;
    nvvm_f2ui_rm_ftz =  float -> uint;
    nvvm_f2ui_rn =  float -> uint;
    nvvm_f2ui_rn_ftz =  float -> uint;
    nvvm_f2ui_rp =  float -> uint;
    nvvm_f2ui_rp_ftz =  float -> uint;
    nvvm_f2ui_rz =  float -> uint;
    nvvm_f2ui_rz_ftz =  float -> uint;
    nvvm_brev32 =  uint -> uint;
    nvvm_max_ui =  {uint,uint} -> uint;
    nvvm_min_ui =  {uint,uint} -> uint;
    nvvm_mul24_ui =  {uint,uint} -> uint;
    nvvm_mulhi_ui =  {uint,uint} -> uint;
    nvvm_prmt =  {uint,uint,uint} -> uint;
    nvvm_sad_ui =  {uint,uint,uint} -> uint;
    nvvm_d2ull_rm =  double -> uint64;
    nvvm_d2ull_rn =  double -> uint64;
    nvvm_d2ull_rp =  double -> uint64;
    nvvm_d2ull_rz =  double -> uint64;
    nvvm_f2ull_rm =  float -> uint64;
    nvvm_f2ull_rm_ftz =  float -> uint64;
    nvvm_f2ull_rn =  float -> uint64;
    nvvm_f2ull_rn_ftz =  float -> uint64;
    nvvm_f2ull_rp =  float -> uint64;
    nvvm_f2ull_rp_ftz =  float -> uint64;
    nvvm_f2ull_rz =  float -> uint64;
    nvvm_f2ull_rz_ftz =  float -> uint64;
    nvvm_brev64 =  uint64 -> uint64;
    nvvm_max_ull =  {uint64,uint64} -> uint64;
    nvvm_min_ull =  {uint64,uint64} -> uint64;
    nvvm_mulhi_ull =  {uint64,uint64} -> uint64;
    nvvm_f2h_rn =  float -> uint16;
    nvvm_f2h_rn_ftz =  float -> uint16;
    cuda_syncthreads =  {} -> {};
    nvvm_barrier0 =  {} -> {};
    nvvm_membar_cta =  {} -> {};
    nvvm_membar_gl =  {} -> {};
    nvvm_membar_sys =  {} -> {};
    nvvm_ptr_shared_to_gen_p0i8_p3i8 = terralib.types.pointer(opaque,3) -> &opaque;
    nvvm_ptr_constant_to_gen_p0i8_p4i8 = terralib.types.pointer(opaque,4) -> &opaque;
} ]]

-- handle loading most of the cuda infrastructure lazily to speed initialization time for non-cuda use
local builtintable
setmetatable(cudalib, { __index = function(self,builtin)
    if not rawget(self,"compile") then
        -- load the terra-based libraries
        assert(terralib.loadstring(terracode))()
        return self[builtin]
    end
    if not builtintable then
        builtintable = terra.loadstring(builtintablestring)()
    end
    local typ = builtintable[builtin]
    if not typ then
        error("unknown builtin: "..builtin,2)
    end
    local rename = "llvm."..builtin:gsub("_",".")
    local result = terra.intrinsic(rename,typ)
    self[builtin] = result
    return result
end })
