local const = cudalib.constantmemory(float, 1)

local terra kernel(data: &float)
end

local M = terralib.cudacompile({
    kernel = kernel,
    const = const
})
