-- This is an attempt to be more systematic about checking Terra's
-- calling convention support, particularly against C.
--
-- The test covers:
--
--  * Pass no arguments and return void.
--
--  * Pass/return an empty struct.
--
--  * For each type in {int8, int16, int32, int64, float, double}:
--      * Pass 1..N scalar arguments of this type, and return the same type.
--
--  * For each type in {int8, int16, int32, int64, float, double}:
--      * Pass (and return) a single struct argument with 1..N fields
--        of the type above.
--
--  * For each type in {int8, int16, int32, int64, float, double}:
--      * Pass two struct arguments, as above, and return same struct.
--
--  * As each of the three cases above, but with arguments/fields
--    picked from a rotating set of types.
--
-- A couple notable features (especially compared to cconv.t):
--
--  * The tests verify that structs are passed by value, ensuring
--    modifications within the callee do not affect the caller.
--
--  * As compared to cconv.t, this test verifies that Terra can call both
--    itself and C. The latter is particularly important for ensuring we match
--    the ABI of the system C compiler.
--
--  * As a bonus, the use of C enables comparisons between Clang's and
--    Terra's output. A command to generate the LLVM IR is shown (commented)
--    at the bottom of the file.

local MAX_N = 12 -- Needs to be <= 22 to avoid overflowing uint8.

local ctypes = {
  [uint8] = "uint8_t",
  [int16] = "int16_t",
  [int32] = "int32_t",
  [int64] = "int64_t",
  [float] = "float",
  [double] = "double",
}

local function generate_uniform_struct(name, typ, N)
  local parts = terralib.newlist({"typedef struct " .. name .. N .. " {"})
  for i = 1, N do
    parts:insert(ctypes[typ] .. " f" .. i .. ";")
  end
  parts:insert("} " .. name .. N .. ";")
  return parts:concat(" ")
end

local function generate_nonuniform_struct(name, types, N)
  local parts = terralib.newlist({"typedef struct " .. name .. N .. " {"})
  for i = 1, N do
    local typ = types[((i - 1) % #types) + 1]
    parts:insert(ctypes[typ] .. " f" .. i .. ";")
  end
  parts:insert("} " .. name .. N .. ";")
  return parts:concat(" ")
end

local function generate_void_function(name)
  return "void " .. name .. "() {}"
end

local function generate_uniform_scalar_function(name, typ, N)
  local arglist = terralib.newlist()
  for i = 1, N do
    arglist:insert(ctypes[typ] .. " x" .. i)
  end
  local exprlist = terralib.newlist()
  for i = 1, N do
    exprlist:insert("x" .. i)
  end
  return ctypes[typ] .. " " .. name .. N .. "(" .. arglist:concat(", ") .. ") { return " .. exprlist:concat(" + ") .. "; }"
end

local function generate_nonuniform_scalar_function(name, types, N)
  local arglist = terralib.newlist()
  for i = 1, N do
    local typ = types[((i - 1) % #types) + 1]
    arglist:insert(ctypes[typ] .. " x" .. i)
  end
  local exprlist = terralib.newlist()
  for i = 1, N do
    exprlist:insert("x" .. i)
  end
  return "double " .. name .. N .. "(" .. arglist:concat(", ") .. ") { return " .. exprlist:concat(" + ") .. "; }"
end

local function generate_aggregate_one_arg_function(name, aggname, N)
  local statlist = terralib.newlist()
  for i = 1, N do
    statlist:insert("x.f" .. i .. " += " .. i .. ";")
  end
  return aggname .. N .. " " .. name .. N .. "(" .. aggname .. N .. " x) { " .. statlist:concat(" ") .. " return x; }"
end

local function generate_aggregate_two_arg_function(name, aggname, N)
  local statlist = terralib.newlist()
  for i = 1, N do
    statlist:insert("x.f" .. i .. " += y.f" .. i .. ";")
  end
  return aggname .. N .. " " .. name .. N .. "(" .. aggname .. N .. " x, " .. aggname .. N .. " y) { " .. statlist:concat(" ") .. " return x; }"
end

local uniform_names = terralib.newlist({"q", "r", "s", "t", "u", "v"})
local types = {uint8, int16, int32, int64, float, double}

local nonuniform_names = terralib.newlist({"w", "x"})
local type_rotations = {
  {uint8, int16, int32, int64, double},
  {float, float, uint8, uint8, int16, int32, int64},
}

local all_names = terralib.newlist()
all_names:insertall(uniform_names)
all_names:insertall(nonuniform_names)

local uniform_scalar_names = terralib.newlist({"b", "c", "d", "e", "f", "g"})

local nonuniform_scalar_names = terralib.newlist({"h", "i"})

local all_scalar_names = terralib.newlist()
all_scalar_names:insertall(uniform_scalar_names)
all_scalar_names:insertall(nonuniform_scalar_names)

local c
do
  local definitions = terralib.newlist({"#include <stdint.h>", ""})

  definitions:insert(generate_uniform_struct("p", nil, 0))
  definitions:insert("")

  for i, typ in ipairs(types) do
    local name = uniform_names[i]
    for N = 1, MAX_N do
      definitions:insert(generate_uniform_struct(name, typ, N))
    end
    definitions:insert("")
  end

  for i, type_rotation in ipairs(type_rotations) do
    local name = nonuniform_names[i]
    for N = 1, MAX_N do
      definitions:insert(generate_nonuniform_struct(name, type_rotation, N))
    end
    definitions:insert("")
  end

  definitions:insert(generate_void_function("ca0"))
  definitions:insert("")

  for i, typ in ipairs(types) do
    local name = uniform_scalar_names[i]
    for N = 1, MAX_N do
      definitions:insert(generate_uniform_scalar_function("c" .. name, typ, N))
    end
    definitions:insert("")
  end

  for i, type_rotation in ipairs(type_rotations) do
    local name = nonuniform_scalar_names[i]
    for N = 1, MAX_N do
      definitions:insert(
        generate_nonuniform_scalar_function("c" .. name, type_rotation, N))
    end
    definitions:insert("")
  end

  definitions:insert(generate_aggregate_one_arg_function("cp", "p", 0))
  definitions:insert("")

  for _, name in ipairs(all_names) do
    for N = 1, MAX_N do
      definitions:insert(
        generate_aggregate_one_arg_function("c" .. name, name, N))
    end
    definitions:insert("")
  end

  for _, name in ipairs(all_names) do
    for N = 1, MAX_N do
      definitions:insert(
        generate_aggregate_two_arg_function("c2" .. name, name, N))
    end
    definitions:insert("")
  end

  c = terralib.includecstring(definitions:concat("\n"))
end

local function generate_void_terra(mod, name)
  local terra f() end
  f:setname(name)
  f:setinlined(false)
  mod[name] = f
end

local function generate_uniform_scalar_terra(mod, name, typ, N)
  local args = terralib.newlist()
  for i = 1, N do
    args:insert(terralib.newsymbol(typ, "x" .. i))
  end
  local terra f([args])
    return [args:reduce(function(x, y) return `x + y end)]
  end
  f:setname(name .. N)
  f:setinlined(false)
  mod[name .. N] = f
end

local function generate_nonuniform_scalar_terra(mod, name, types, N)
  local args = terralib.newlist()
  for i = 1, N do
    local typ = types[((i - 1) % #types) + 1]
    args:insert(terralib.newsymbol(typ, "x" .. i))
  end
  local terra f([args])
    return [args:reduce(function(x, y) return `x + y end)]
  end
  f:setname(name .. N)
  f:setinlined(false)
  mod[name .. N] = f
end

local function generate_aggregate_one_arg_terra(mod, name, aggtyp, N)
  local terra f(x : aggtyp)
    escape
      for i = 1, N do
        local field = "f" .. i
        emit quote x.[field] = x.[field] + i end
      end
    end
    return x
  end
  f:setname(name .. N)
  f:setinlined(false)
  mod[name .. N] = f
end

local function generate_aggregate_two_arg_terra(mod, name, aggtyp, N)
  local terra f(x : aggtyp, y : aggtyp)
    escape
      for i = 1, N do
        local field = "f" .. i
        emit quote x.[field] = x.[field] + y.[field] end
      end
    end
    return x
  end
  f:setname(name .. N)
  f:setinlined(false)
  mod[name .. N] = f
end

local t = {}

generate_void_terra(t, "ta0")

for i, typ in ipairs(types) do
  local name = uniform_scalar_names[i]
  for N = 1, MAX_N do
    generate_uniform_scalar_terra(t, "t" .. name, typ, N)
  end
end

for i, type_rotation in ipairs(type_rotations) do
  local name = nonuniform_scalar_names[i]
  for N = 1, MAX_N do
    generate_nonuniform_scalar_terra(t, "t" .. name, type_rotation, N)
  end
end

generate_aggregate_one_arg_terra(t, "tp", c["p0"], 0)

for _, name in ipairs(all_names) do
  for N = 1, MAX_N do
    generate_aggregate_one_arg_terra(t, "t" .. name, c[name .. N], N)
  end
end

for _, name in ipairs(all_names) do
  for N = 1, MAX_N do
    generate_aggregate_two_arg_terra(t, "t2" .. name, c[name .. N], N)
  end
end

-- Generate a unique exit condition for each test site.
local exit_condition = 1
local teq = macro(
  function(arg, value)
    exit_condition = exit_condition + 1
    return quote
      if arg ~= value then
        return exit_condition -- failure
      end
    end
  end)

local init_fields = macro(
  function(arg, value, num_fields)
    return quote
      escape
        for i = 1, num_fields:asvalue() do
          emit quote
            arg.["f"..i] = value*i
          end
        end
      end
    end
  end)

local check_fields = macro(
  function(arg, value, num_fields)
    return quote
      escape
        for i = 1, num_fields:asvalue() do
          emit quote
            teq(arg.["f"..i], value*i)
          end
        end
      end
    end
  end)

-- Check functions with zero arguments/fields.
terra check_zero()
  c.ca0()
  t.ta0()

  var x0 : c.p0
  var cx0 = c.cp0(x0)
  var tx0 = t.tp0(x0)
end
check_zero()

-- Check functions of scalar arguments.
for _, name in ipairs(all_scalar_names) do
  for N = 1, MAX_N do
    local arglist = terralib.newlist()
    local expected_result = 0
    for i = 1, N do
      arglist:insert(i)
      expected_result = expected_result + i
    end
    assert(expected_result < 255, "value is too large to fit in uint8, not safe to test")
    local cfunc = c["c" .. name .. N]
    local tfunc = t["t" .. name .. N]
    local terra check()
      teq(cfunc(arglist), expected_result)
      teq(tfunc(arglist), expected_result)
      return 0
    end
    local ok = check()
    if ok ~= 0 then
      print(terralib.saveobj(nil, "llvmir", {check=check}, nil, nil, false))
      error("scalar test failed for N=" .. tostring(N) .. ", " .. tostring(tfunc:gettype()) .. ": error code " .. tostring(ok))
    end
  end
end

-- Check functions of one aggregate argument.
for _, name in ipairs(all_names) do
  for N = 1, MAX_N do
    local aggtyp = c[name .. N]
    local cfunc = c["c" .. name .. N]
    local tfunc = t["t" .. name .. N]
    assert(11 * N < 255, "value is too large to fit in uint8, not safe to test")
    local terra check()
      var x : aggtyp
      init_fields(x, 10, N)
      var cx = cfunc(x)
      check_fields(x, 10, N)
      check_fields(cx, 11, N)
      var tx = tfunc(x)
      check_fields(x, 10, N)
      check_fields(tx, 11, N)
      return 0
    end
    local ok = check()
    if ok ~= 0 then
      print(terralib.saveobj(nil, "llvmir", {check=check}, nil, nil, false))
      error("aggregate test failed for N=" .. tostring(N) .. ", " .. tostring(tfunc:gettype()) .. " where " .. tostring(aggtyp) .. "=" .. tostring(aggtyp:getentries():map(function(f) return tostring(f.field) .. "=" .. tostring(f.type) end)) .. ": error code " .. tostring(ok))
    end
  end
end

-- Check functions of two aggregate arguments.
for _, name in ipairs(all_names) do
  for N = 1, MAX_N do
    local aggtyp = c[name .. N]
    local cfunc = c["c2" .. name .. N]
    local tfunc = t["t2" .. name .. N]
    assert(11 * N < 255, "value is too large to fit in uint8, not safe to test")
    local terra check()
      var x : aggtyp
      init_fields(x, 10, N)
      var y : aggtyp
      init_fields(y, 1, N)
      var cx = cfunc(x, y)
      check_fields(x, 10, N)
      check_fields(cx, 11, N)
      var tx = tfunc(x, y)
      check_fields(x, 10, N)
      check_fields(tx, 11, N)
      return 0
    end
    local ok = check()
    if ok ~= 0 then
      print(terralib.saveobj(nil, "llvmir", {check=check}, nil, nil, false))
      error("aggregate test failed for N=" .. tostring(N) .. ", " .. tostring(tfunc:gettype()) .. " where " .. tostring(aggtyp) .. "=" .. tostring(aggtyp:getentries():map(function(f) return tostring(f.field) .. "=" .. tostring(f.type) end)) .. ": error code " .. tostring(ok))
    end
  end
end
