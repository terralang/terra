-- This is an attempt to be more systematic about checking Terra's
-- calling convention support, particularly against C.
--
-- The test covers:
--
--  * Pass no arguments and return void.
--
--  * Pass/return an empty struct.
--
--  * For T in {uint8, int16, int32, int64, float, double,
--              uint8[2], int16[2], int32[2], int64[2], float[2], double[2]}:
--     1. Pass 1..N arguments of type T, and return T.
--     2. Pass (and return) a single struct argument with 1..N fields of type T.
--     3. Pass two struct arguments, as above, and return same struct.
--
--  * As above, but with arguments/fields picked from a rotating set of types.
--
--  * Note: arrays (uint8[2], etc.) passed as individual arguments (not struct
--    fields) are wrapped in a single-field struct because otherwise C arrays
--    are passed by reference. While Terra is capable of passing such types by
--    value, C is not, so there is no way to do a comparison.
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

local MAX_N = 9 -- Needs to be <= 23 to avoid overflowing uint8.
local MAX_ARRAY_N = 4

local ctypes = {
  [uint8] = "uint8_t",
  [int16] = "int16_t",
  [int32] = "int32_t",
  [int64] = "int64_t",
  [float] = "float",
  [double] = "double",
}

local function lookup_scalar(typ)
  if typ:isarray() then
    return lookup_scalar(typ.type) .. "_" .. tostring(typ.N)
  end
  return ctypes[typ]
end

local function lookup_scalar_base(typ)
  if typ:isarray() then
    return lookup_scalar_base(typ.type)
  end
  return ctypes[typ]
end

local function lookup_field(typ)
  if not typ then return end
  if typ:isarray() then
    local prefix, suffix = lookup_field(typ.type)
    return prefix, suffix .. "[" .. typ.N .. "]"
  end
  return ctypes[typ], ""
end

local function get_type_in_rotation(types, i)
  return types[((i - 1) % #types) + 1]
end


local function generate_array_wrapper(typ, N)
  local name = lookup_scalar(typ) .. "_"
  local parts = terralib.newlist({"typedef struct " .. name .. N .. " {"})
  local prefix, suffix = lookup_field(typ[N])
  parts:insert(prefix .. " x" .. suffix .. ";")
  parts:insert("} " .. name .. N .. ";")
  return parts:concat(" ")
end

local function generate_uniform_struct(name, typ, N)
  local parts = terralib.newlist({"typedef struct " .. name .. N .. " {"})
  local prefix, suffix = lookup_field(typ)
  for i = 1, N do
    parts:insert(prefix .. " f" .. i .. suffix .. ";")
  end
  parts:insert("} " .. name .. N .. ";")
  return parts:concat(" ")
end

local function generate_nonuniform_struct(name, types, N)
  local parts = terralib.newlist({"typedef struct " .. name .. N .. " {"})
  for i = 1, N do
    local typ = get_type_in_rotation(types, i)
    local prefix, suffix = lookup_field(typ)
    parts:insert(prefix .. " f" .. i .. suffix .. ";")
  end
  parts:insert("} " .. name .. N .. ";")
  return parts:concat(" ")
end

local function generate_void_function(name)
  return "void " .. name .. "() {}"
end

local function generate_scalar_exprs(argname, typ, exprlist)
  if typ:isarray() then
    for j = 0, typ.N-1 do
      exprlist:insert(argname .. ".x[" .. j .. "]")
    end
  else
    exprlist:insert(argname)
  end
end

local function generate_uniform_scalar_function(name, typ, N)
  local arglist = terralib.newlist()
  for i = 1, N do
    arglist:insert(lookup_scalar(typ) .. " x" .. i)
  end
  local exprlist = terralib.newlist()
  for i = 1, N do
    generate_scalar_exprs("x" .. i, typ, exprlist)
  end
  return lookup_scalar_base(typ) .. " " .. name .. N .. "(" .. arglist:concat(", ") .. ") { return " .. exprlist:concat(" + ") .. "; }"
end

local function generate_nonuniform_scalar_function(name, types, N)
  local arglist = terralib.newlist()
  for i = 1, N do
    local typ = get_type_in_rotation(types, i)
    arglist:insert(lookup_scalar(typ) .. " x" .. i)
  end
  local exprlist = terralib.newlist()
  for i = 1, N do
    local typ = get_type_in_rotation(types, i)
    generate_scalar_exprs("x" .. i, typ, exprlist)
  end
  return "double " .. name .. N .. "(" .. arglist:concat(", ") .. ") { return " .. exprlist:concat(" + ") .. "; }"
end

local function generate_aggregate_one_field_stat(field, inc, typ, statlist)
  if typ:isarray() then
    for j = 0, typ.N-1 do
      statlist:insert(field .. "[" .. j .. "] += " .. inc .. ";")
    end
  else
    statlist:insert(field .. " += " .. inc .. ";")
  end
end

local function generate_uniform_aggregate_one_arg_function(name, aggname, typ, N)
  local statlist = terralib.newlist()
  for i = 1, N do
    generate_aggregate_one_field_stat("x.f" .. i, i, typ, statlist)
  end
  return aggname .. N .. " " .. name .. N .. "(" .. aggname .. N .. " x) { " .. statlist:concat(" ") .. " return x; }"
end

local function generate_nonuniform_aggregate_one_arg_function(name, aggname, types, N)
  local statlist = terralib.newlist()
  for i = 1, N do
    local typ = get_type_in_rotation(types, i)
    generate_aggregate_one_field_stat("x.f" .. i, i, typ, statlist)
  end
  return aggname .. N .. " " .. name .. N .. "(" .. aggname .. N .. " x) { " .. statlist:concat(" ") .. " return x; }"
end

local function generate_aggregate_two_field_stat(field1, field2, typ, statlist)
  if typ:isarray() then
    for j = 0, typ.N-1 do
      statlist:insert(field1 .. "[" .. j .. "] += " .. field2 .. "[" .. j .. "];")
    end
  else
    statlist:insert(field1 .. " += " .. field2 .. ";")
  end
end

local function generate_uniform_aggregate_two_arg_function(name, aggname, typ, N)
  local statlist = terralib.newlist()
  for i = 1, N do
    generate_aggregate_two_field_stat("x.f" .. i, "y.f" .. i, typ, statlist)
  end
  return aggname .. N .. " " .. name .. N .. "(" .. aggname .. N .. " x, " .. aggname .. N .. " y) { " .. statlist:concat(" ") .. " return x; }"
end

local function generate_nonuniform_aggregate_two_arg_function(name, aggname, types, N)
  local statlist = terralib.newlist()
  for i = 1, N do
    local typ = get_type_in_rotation(types, i)
    generate_aggregate_two_field_stat("x.f" .. i, "y.f" .. i, typ, statlist)
  end
  return aggname .. N .. " " .. name .. N .. "(" .. aggname .. N .. " x, " .. aggname .. N .. " y) { " .. statlist:concat(" ") .. " return x; }"
end

local base_types = {uint8, int16, int32, int64, float, double}

local uniform_names = terralib.newlist({"p", "q", "r", "s", "t", "u",
                                        "pp", "qq", "rr", "ss", "tt", "uu"})
local types = {uint8, int16, int32, int64, float, double,
               uint8[2], int16[2], int32[2], int64[2], float[2], double[2]}

local nonuniform_names = terralib.newlist({"v", "w", "x", "y", "z"})
local type_rotations = {
  {uint8, int16, int32, int64, double},
  {float, float, uint8, uint8, int16, int32, int64},
  {uint8, int16[2], int64, float[3], double[2]},
  {float, float[2]},
  {double, double[4]},
}

local all_names = terralib.newlist()
all_names:insertall(uniform_names)
all_names:insertall(nonuniform_names)

local uniform_scalar_names = terralib.newlist({"b", "c", "d", "e", "f", "g",
                                               "bb", "cc", "dd", "ee", "ff", "gg"})

local nonuniform_scalar_names = terralib.newlist({"h", "i", "j", "k", "kk"})

local all_scalar_names = terralib.newlist()
all_scalar_names:insertall(uniform_scalar_names)
all_scalar_names:insertall(nonuniform_scalar_names)

local c
do
  local definitions = terralib.newlist({"#include <stdint.h>", ""})

  definitions:insert(generate_uniform_struct("p", nil, 0))
  definitions:insert("")

  for i, typ in ipairs(base_types) do
    for N = 1, MAX_ARRAY_N do
      definitions:insert(generate_array_wrapper(typ, N))
    end
    definitions:insert("")
  end

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

  definitions:insert(generate_uniform_aggregate_one_arg_function("cp", "p", nil, 0))
  definitions:insert("")

  for i, typ in ipairs(types) do
    local name = uniform_names[i]
    for N = 1, MAX_N do
      definitions:insert(
        generate_uniform_aggregate_one_arg_function("c" .. name, name, typ, N))
    end
    definitions:insert("")
  end

  for i, type_rotation in ipairs(type_rotations) do
    local name = nonuniform_names[i]
    for N = 1, MAX_N do
      definitions:insert(
        generate_nonuniform_aggregate_one_arg_function("c" .. name, name, type_rotation, N))
    end
    definitions:insert("")
  end

  for i, typ in ipairs(types) do
    local name = uniform_names[i]
    for N = 1, MAX_N do
      definitions:insert(
        generate_uniform_aggregate_two_arg_function("c2" .. name, name, typ, N))
    end
    definitions:insert("")
  end

  for i, type_rotation in ipairs(type_rotations) do
    local name = nonuniform_names[i]
    for N = 1, MAX_N do
      definitions:insert(
        generate_nonuniform_aggregate_two_arg_function("c2" .. name, name, type_rotation, N))
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

local function lookup_scalar_terra(typ)
  if typ:isarray() then
    return c[lookup_scalar(typ)]
  end
  return typ
end

local function generate_scalar_exprs_terra(arg, typ, exprlist)
  if typ:isarray() then
    for j = 0, typ.N-1 do
      exprlist:insert(`arg.x[j])
    end
  else
    exprlist:insert(arg)
  end
end

local function generate_uniform_scalar_terra(mod, name, typ, N)
  local argtype = lookup_scalar_terra(typ)
  local args = terralib.newlist()
  for i = 1, N do
    args:insert(terralib.newsymbol(argtype, "x" .. i))
  end
  local exprlist = terralib.newlist()
  for _, arg in ipairs(args) do
    generate_scalar_exprs_terra(arg, typ, exprlist)
  end
  local terra f([args])
    return [exprlist:reduce(function(x, y) return `x + y end)]
  end
  f:setname(name .. N)
  f:setinlined(false)
  mod[name .. N] = f
end

local function generate_nonuniform_scalar_terra(mod, name, types, N)
  local args = terralib.newlist()
  for i = 1, N do
    local typ = get_type_in_rotation(types, i)
    local argtype = lookup_scalar_terra(typ)
    args:insert(terralib.newsymbol(argtype, "x" .. i))
  end
  local exprlist = terralib.newlist()
  for i, arg in ipairs(args) do
    local typ = get_type_in_rotation(types, i)
    generate_scalar_exprs_terra(arg, typ, exprlist)
  end
  local terra f([args])
    return [exprlist:reduce(function(x, y) return `x + y end)]
  end
  f:setname(name .. N)
  f:setinlined(false)
  mod[name .. N] = f
end

local function generate_aggregate_one_field_stats_terra(field, typ, inc, statlist)
  if typ:isarray() then
    for j = 0, typ.N-1 do
      statlist:insert(quote [field][j] = [field][j] + inc end)
    end
  else
    statlist:insert(quote [field] = [field] + inc end)
  end
end

local function generate_aggregate_one_arg_terra(mod, name, aggtyp, N)
  local terra f(x : aggtyp)
    escape
      local statlist = terralib.newlist()
      for i = 1, N do
        local field = `x.["f" .. i]
        local ftype = field:gettype()
        generate_aggregate_one_field_stats_terra(field, ftype, i, statlist)
      end
      emit quote [statlist] end
    end
    return x
  end
  f:setname(name .. N)
  f:setinlined(false)
  mod[name .. N] = f
end

local function generate_aggregate_two_field_stats_terra(field1, field2, typ, statlist)
  if typ:isarray() then
    for j = 0, typ.N-1 do
      statlist:insert(quote [field1][j] = [field1][j] + [field2][j] end)
    end
  else
    statlist:insert(quote [field1] = [field1] + [field2] end)
  end
end

local function generate_aggregate_two_arg_terra(mod, name, aggtyp, N)
  local terra f(x : aggtyp, y : aggtyp)
    escape
      local statlist = terralib.newlist()
      for i = 1, N do
        local fname = "f" .. i
        local field1 = `x.["f" .. i]
        local field2 = `y.["f" .. i]
        local ftype = field1:gettype()
        generate_aggregate_two_field_stats_terra(field1, field2, ftype, statlist)
      end
      emit quote [statlist] end
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
local function generate_teq(arg, value)
  exit_condition = exit_condition + 1
  return quote
    if arg ~= value then
      return exit_condition -- failure
    end
  end
end
local teq = macro(generate_teq)

local function generate_field_init(field, typ, init, statlist)
  if typ:isarray() then
    for j = 0, typ.N-1 do
      statlist:insert(quote field[j] = init end)
    end
  else
    statlist:insert(quote field = init end)
  end
end

local init_fields = macro(
  function(arg, value, num_fields)
    local statlist = terralib.newlist()
    for i = 1, num_fields:asvalue() do
      local field = `arg.["f" .. i]
      local ftype = field:gettype()
      generate_field_init(field, ftype, `value*i, statlist)
    end

    return quote [statlist] end
  end)

local function generate_field_check(field, typ, expected, statlist)
  if typ:isarray() then
    for j = 0, typ.N-1 do
      statlist:insert(generate_teq(`field[j], expected))
    end
  else
    statlist:insert(generate_teq(field, expected))
  end
end

local check_fields = macro(
  function(arg, value, num_fields)
    local statlist = terralib.newlist()
    for i = 1, num_fields:asvalue() do
      local field = `arg.["f" .. i]
      local ftype = field:gettype()
      generate_field_check(field, ftype, `value*i, statlist)
    end
    return quote [statlist] end
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

local function generate_scalar_args(typ, i, arglist)
  if typ:isarray() then
    local expected_result = 0
    local values = terralib.newlist()
    for j = 0, typ.N-1 do
      values:insert(i)
      expected_result = expected_result + i
    end
    local arrtyp = lookup_scalar_terra(typ)
    arglist:insert(`arrtyp { x = arrayof(typ.type, values) })
    return expected_result
  end

  arglist:insert(i)
  return i
end

local function safe_limit(typ)
  if typ:isarray() then
    return safe_limit(typ.type)
  end
  -- Overapproximate range of float/double. This is ok because we'll
  -- never get close to this limit.
  return 2ULL ^ (sizeof(typ)*8) - 1
end

local function min(a, b, c, d)
  if a < b then return a, c end
  return b, d
end

-- Check functions of scalar arguments.
for i, typ in ipairs(types) do
  local name = uniform_scalar_names[i]
  for N = 1, MAX_N do
    local cfunc = c["c" .. name .. N]
    local tfunc = t["t" .. name .. N]
    local arglist = terralib.newlist()
    local expected_result = 0
    for i = 1, N do
      expected_result = expected_result + generate_scalar_args(typ, i, arglist)
    end
    local limit = safe_limit(typ)
    local test_name = "N=" .. tostring(N) .. ", " .. tostring(tfunc:gettype())
    if expected_result < limit then
      print("running scalar test for " .. test_name)
      local terra check()
        teq(cfunc(arglist), expected_result)
        teq(tfunc(arglist), expected_result)
        return 0
      end
      local ok = check()
      if ok ~= 0 then
        print(terralib.saveobj(nil, "llvmir", {check=check}, nil, nil, false))
        error("scalar test failed for " .. test_name .. ": error code " .. tostring(ok))
      end
    else
      print("skipping scalar test for " .. test_name .. ": " .. expected_result .. " is too large for " .. tostring(typ) .. " " .. tostring(limit))
    end
  end
end
for i, type_rotation in ipairs(type_rotations) do
  local name = nonuniform_scalar_names[i]
  for N = 1, MAX_N do
    local cfunc = c["c" .. name .. N]
    local tfunc = t["t" .. name .. N]
    local arglist = terralib.newlist()
    local expected_result = 0
    local limit, limit_type = math.huge
    for i = 1, N do
      local typ = get_type_in_rotation(type_rotation, i)
      expected_result = expected_result + generate_scalar_args(typ, i, arglist)
      limit, limit_type = min(limit, safe_limit(typ), limit_type, typ)
    end
    local test_name = "N=" .. tostring(N) .. ", " .. tostring(tfunc:gettype())
    if expected_result < limit then
      print("running scalar test for " .. test_name)
      local terra check()
        teq(cfunc(arglist), expected_result)
        teq(tfunc(arglist), expected_result)
        return 0
      end
      local ok = check()
      if ok ~= 0 then
        print(terralib.saveobj(nil, "llvmir", {check=check}, nil, nil, false))
        error("scalar test failed for " .. test_name .. ": error code " .. tostring(ok))
      end
    else
      print("skipping scalar test for " .. test_name .. ": " .. expected_result .. " is too large for " .. tostring(limit_type) .. " " .. tostring(limit))
    end
  end
end

-- Check functions of one aggregate argument.
for _, name in ipairs(all_names) do
  for N = 1, MAX_N do
    local aggtype = c[name .. N]
    local cfunc = c["c" .. name .. N]
    local tfunc = t["t" .. name .. N]
    local test_name = "N=" .. tostring(N) .. ", " .. tostring(tfunc:gettype()) .. " where " .. tostring(aggtype) .. "=" .. tostring(aggtype:getentries():map(function(f) return tostring(f.field) .. "=" .. tostring(f.type) end))
    print("running aggregate test for " .. test_name)
    assert(11 * N < 255, "value is too large to fit in uint8, not safe to test")
    local terra check()
      var x : aggtype
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
      error("aggregate test failed for " .. test_name .. ": error code " .. tostring(ok))
    end
  end
end

-- Check functions of two aggregate arguments.
for _, name in ipairs(all_names) do
  for N = 1, MAX_N do
    local aggtype = c[name .. N]
    local cfunc = c["c2" .. name .. N]
    local tfunc = t["t2" .. name .. N]
    local test_name = "N=" .. tostring(N) .. ", " .. tostring(tfunc:gettype()) .. " where " .. tostring(aggtype) .. "=" .. tostring(aggtype:getentries():map(function(f) return tostring(f.field) .. "=" .. tostring(f.type) end))
    print("running aggregate test for " .. test_name)
    assert(11 * N < 255, "value is too large to fit in uint8, not safe to test")
    local terra check()
      var x : aggtype
      init_fields(x, 10, N)
      var y : aggtype
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
      error("aggregate test failed for " .. test_name .. ": error code " .. tostring(ok))
    end
  end
end
