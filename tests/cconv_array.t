-- Test arrays passed (returned) by value: these are not supported by
-- C, but Terra supports them and so has to implement them at least in
-- a self-consistent way.

local test = require("test")

local function run_test_case(typ, N)
  print("running test for " .. tostring(typ[N]))
  local terra callee(x : typ[N])
    escape
      for i = 1, N do
        emit quote
          x[i-1] = x[i-1] + i
        end
      end
    end
    return x
  end
  callee:setinlined(false)

  local args = terralib.newlist()
  for i = 1, N do
    args:insert(terralib.newsymbol(typ))
  end
  local terra caller([args])
    var y : typ[N]
    escape
      for i = 1, N do
        emit quote
          y[i-1] = [args[i]]
        end
      end
    end
    var z = callee(y)
    return [(
      function()
        local result = terralib.newlist()
        for i = 1, N do
          result:insert(`y[i-1])
        end
        for i = 1, N do
          result:insert(`z[i-1])
        end
        return result
      end)()]
  end

  local values = terralib.newlist()
  for i = 1, N do
    values:insert(i * 10)
  end

  local values = terralib.newlist({unpacktuple(caller(unpack(values)))})

  for i = 1, N do
    test.eq(values[i], i*10)
  end
  for i = N+1, 2*N do
    test.eq(values[i], (i-N)*11)
  end
end

local MAX_N_INT8 = 11
local MAX_N_SMALL = 32
local ffi = require('ffi')
if ffi.os == 'OSX' and ffi.arch == 'arm64' then
  MAX_N_INT8 = 8 -- https://github.com/terralang/terra/issues/604
  MAX_N_SMALL = 8 -- https://github.com/terralang/terra/issues/604
end

for N = 0, MAX_N_INT8 do
  run_test_case(int8, N)
end
for _, typ in ipairs({int16, int32, float}) do
  for N = 0, MAX_N_SMALL do
    run_test_case(typ, N)
  end
end
for _, typ in ipairs({int64, double}) do
  for N = 0, 32 do
    run_test_case(typ, N)
  end
end
