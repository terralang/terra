-- See Copyright Notice in ../LICENSE.txt
function terralib.cudacompile(module)
    local tbl = {}
    for k,v in pairs(module) do
        if not terra.isfunction(v) then
            error("module must contain only terra functions")
        end
        v:emitllvm()
        local definitions =  v:getdefinitions()
        if #definitions > 1 then
            error("cuda kernels cannot be polymorphic, but found polymorphic function "..k)
        end
        local fn = definitions[1]
        local success,typ = fn:peektype() -- calling gettype would JIT the function, which we don't want
                                    -- we should modify gettype to allow the return of a type for a non-jitted function
        assert(success)

        if not typ.returntype:isunit() then
            error(k..": kernels must return no arguments.")
        end

        for _,p in ipairs(typ.parameters) do
            if not p:ispointer() or p:isprimitive() then
                error(k..": kernels arguments can only be primitive types or pointers but kernel has type ", typ)
            end
        end
        tbl[k] = definitions[1]
    end
    --call into tcuda.cpp to perform compilation
    return terralib.cudacompileimpl(tbl)
end






--we need to use terra to write the function that JITs the right wrapper functions for CUDA kernels
--since this file is loaded as Lua, we use terra.loadstring to inject some terra code
local terracode = terra.loadstring [[
local C --load cuda header lazily to speed startup time
struct terralib.CUDAParams {
    gridDimX : uint,  gridDimY : uint,  gridDimZ : uint,
    blockDimX : uint, blockDimY : uint, blockDimZ : uint,
    sharedMemBytes : uint, hStream :  &opaque
}
function terralib.cudamakekernelwrapper(fn,funcdata)
    if not C then
        C = terralib.includec("cuda.h")    
    end
    local _,typ = fn:peektype()
    local arguments = typ.parameters:map(symbol)
    
    local paramctor = arguments:map(function(s) return `&s end)
    return terra(params : &terralib.CUDAParams, [arguments])
        
        var func : &C.CUfunction = [&C.CUfunction](funcdata)
        var paramlist = arrayof([&opaque],[paramctor])
        return C.cuLaunchKernel(@func,params.gridDimX,params.gridDimY,params.gridDimZ,
                                     params.blockDimX,params.blockDimY,params.blockDimZ,
                                     params.sharedMemBytes, C.CUstream(params.hStream),paramlist,nil)
    end
end 

]]
terracode()

local builtintablestring = nil --at the end of the file
local builtintable
cudalib = setmetatable({}, { __index = function(self,builtin)
    if not builtintable then
        builtintable = terra.loadstring(builtintablestring)()
    end
    local typ = builtintable[builtin]
    if not typ then
        error("unknown builtin: "..builtin,2)
    end
    local rename = "llvm."..builtin:gsub("_",".")
    print(rename)
    local result = terra.intrinsic(rename,typ)
    self[builtin] = result
    return result
end })

function cudalib.sharedmemory(typ)
    return terralib.global(typ,nil,3)
end




builtintablestring = [[
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
    ptx_bar_sync =  int -> {};
} ]]

