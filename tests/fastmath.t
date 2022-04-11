terra f(x : double, y : double)
  return x + y
end

local function prtable(t)
  local function prinner(i)
    if type(i) == "table" then
      io.write("{")
      local first = true
      for k, v in pairs(i) do
        if first then
          first = false
        else
          io.write(", ")
        end
        prinner(k)
        io.write("=")
        prinner(v)
      end
      io.write("}")
    else
      io.write(tostring(i))
    end
  end
  prinner(t)
  io.write("\n")
end

local function try_compile(opts, check_string)
  print()
  print("############################################################")
  prtable(opts)
  print("############################################################")
  print()
  local ir = terralib.saveobj(nil, "llvmir", {f=f}, nil, nil, opts)
  print(ir)
  assert(string.find(ir, check_string) ~= nil)
end

-- Make sure all the alternative spellings of fastmath are working.
try_compile(nil,                         "fadd double")
try_compile({},                          "fadd double")
try_compile({fastmath=false},            "fadd double")
try_compile({fastmath=true},             "fadd fast double")
try_compile({fastmath="fast"},           "fadd fast double")
try_compile({fastmath="ninf"},           "fadd ninf double")
try_compile({fastmath={}},               "fadd double")
try_compile({fastmath={"ninf", "nnan"}}, "fadd nnan ninf double")
