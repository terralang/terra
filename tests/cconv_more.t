-- This is an attempt to be more systematic about checking Terra's
-- calling convention support, particularly against C.
--
-- The test covers:
--
--  * Pass/return void/no arguments.
--
--  * For each type in {int8, int16, int32, int64, float, double}:
--      * Pass 1..N values as separate arguments to a function, and return the
--        same type.
--
--  * Pass/return an empty struct.
--
--  * For each type in {int8, int16, int32, int64, float, double}:
--      * Pass (and return) a struct with 1..N fields of that type.
--
--  * Same, but with fields of rotating types (int8, int16, int32, int64,
--    double).
--
-- A couple notable features (especially compared to cconv.t):
--
--  * The tests verify that structs are passed by value, by modifying the
--    arguments within the called functions.
--
--  * As compared to cconv.t, this test verifies that Terra can call both
--    itself and C. The latter is particularly important for ensuring we match
--    the ABI of the system C compiler.
--
--  * As a bonus, the use of C allows quick comparisons between Clang's and
--    Terra's output. A command to generate the LLVM IR is shown (commented)
--    at the bottom of the file.

local test = require("test")

local ctypes = {
  [int8] = "int8_t",
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

local uniform_names = {"q", "r", "s", "t", "u", "v"}
local types = {int8, int16, int32, int64, float, double}

local nonuniform_names = {"w", "x"}
local type_rotations = {
  {int8, int16, int32, int64, double},
  {float, float, int8, int8, int16, int32, int64},
}

local uniform_scalar_names = {"b", "c", "d", "e", "f", "g"}

local nonuniform_scalar_names = {"h", "i"}

local c
do
  local definitions = terralib.newlist({"#include <stdint.h>", ""})

  definitions:insert(generate_uniform_struct("p", nil, 0))
  definitions:insert("")

  for i, typ in ipairs(types) do
    local name = uniform_names[i]
    for N = 1, 9 do
      definitions:insert(generate_uniform_struct(name, typ, N))
    end
    definitions:insert("")
  end

  for i, type_rotation in ipairs(type_rotations) do
    local name = nonuniform_names[i]
    for N = 1, 9 do
      definitions:insert(generate_nonuniform_struct(name, type_rotation, N))
    end
    definitions:insert("")
  end

  definitions:insert(generate_void_function("ca0"))
  definitions:insert("")

  for i, typ in ipairs(types) do
    local name = uniform_scalar_names[i]
    for N = 1, 9 do
      definitions:insert(generate_uniform_scalar_function("c" .. name, typ, N))
    end
    definitions:insert("")
  end

  for i, type_rotation in ipairs(type_rotations) do
    local name = nonuniform_scalar_names[i]
    for N = 1, 9 do
      definitions:insert(
        generate_nonuniform_scalar_function("c" .. name, type_rotation, N))
    end
    definitions:insert("")
  end

  definitions:insert(generate_aggregate_one_arg_function("cp", "p", 0))
  definitions:insert("")

  for _, name in ipairs(uniform_names) do
    for N = 1, 9 do
      definitions:insert(
        generate_aggregate_one_arg_function("c" .. name, name, N))
    end
    definitions:insert("")
  end

  for _, name in ipairs(nonuniform_names) do
    for N = 1, 9 do
      definitions:insert(
        generate_aggregate_one_arg_function("c" .. name, name, N))
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

local t = {}

generate_void_terra(t, "ta0")

for i, typ in ipairs(types) do
  local name = uniform_scalar_names[i]
  for N = 1, 9 do
    generate_uniform_scalar_terra(t, "t" .. name, typ, N)
  end
end

for i, type_rotation in ipairs(type_rotations) do
  local name = nonuniform_scalar_names[i]
  for N = 1, 9 do
    generate_nonuniform_scalar_terra(t, "t" .. name, type_rotation, N)
  end
end

generate_aggregate_one_arg_terra(t, "tp", c["p0"], 0)

for _, name in ipairs(uniform_names) do
  for N = 1, 9 do
    generate_aggregate_one_arg_terra(t, "t" .. name, c[name .. N], N)
  end
end

for _, name in ipairs(nonuniform_names) do
  for N = 1, 9 do
    generate_aggregate_one_arg_terra(t, "t" .. name, c[name .. N], N)
  end
end

local qs = {c.q1, c.q2, c.q3, c.q4, c.q5, c.q6, c.q7, c.q8, c.q9}
local cqs = {c.cq1, c.cq2, c.cq3, c.cq4, c.cq5, c.cq6, c.cq7, c.cq8, c.cq9}
local tqs = {t.tq1, t.tq2, t.tq3, t.tq4, t.tq5, t.tq6, t.tq7, t.tq8, t.tq9}

local rs = {c.r1, c.r2, c.r3, c.r4, c.r5, c.r6, c.r7, c.r8, c.r9}
local crs = {c.cr1, c.cr2, c.cr3, c.cr4, c.cr5, c.cr6, c.cr7, c.cr8, c.cr9}
local trs = {t.tr1, t.tr2, t.tr3, t.tr4, t.tr5, t.tr6, t.tr7, t.tr8, t.tr9}

local ss = {c.s1, c.s2, c.s3, c.s4, c.s5, c.s6, c.s7, c.s8, c.s9}
local css = {c.cs1, c.cs2, c.cs3, c.cs4, c.cs5, c.cs6, c.cs7, c.cs8, c.cs9}
local tss = {t.ts1, t.ts2, t.ts3, t.ts4, t.ts5, t.ts6, t.ts7, t.ts8, t.ts9}

local ts = {c.t1, c.t2, c.t3, c.t4, c.t5, c.t6, c.t7, c.t8, c.t9}
local cts = {c.ct1, c.ct2, c.ct3, c.ct4, c.ct5, c.ct6, c.ct7, c.ct8, c.ct9}
local tts = {t.tt1, t.tt2, t.tt3, t.tt4, t.tt5, t.tt6, t.tt7, t.tt8, t.tt9}

local us = {c.u1, c.u2, c.u3, c.u4, c.u5, c.u6, c.u7, c.u8, c.u9}
local cus = {c.cu1, c.cu2, c.cu3, c.cu4, c.cu5, c.cu6, c.cu7, c.cu8, c.cu9}
local tus = {t.tu1, t.tu2, t.tu3, t.tu4, t.tu5, t.tu6, t.tu7, t.tu8, t.tu9}

local vs = {c.v1, c.v2, c.v3, c.v4, c.v5, c.v6, c.v7, c.v8, c.v9}
local cvs = {c.cv1, c.cv2, c.cv3, c.cv4, c.cv5, c.cv6, c.cv7, c.cv8, c.cv9}
local tvs = {t.tv1, t.tv2, t.tv3, t.tv4, t.tv5, t.tv6, t.tv7, t.tv8, t.tv9}

local ws = {c.w1, c.w2, c.w3, c.w4, c.w5, c.w6, c.w7, c.w8, c.w9}
local cws = {c.cw1, c.cw2, c.cw3, c.cw4, c.cw5, c.cw6, c.cw7, c.cw8, c.cw9}
local tws = {t.tw1, t.tw2, t.tw3, t.tw4, t.tw5, t.tw6, t.tw7, t.tw8, t.tw9}

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

-- Part 1: check all of the scalar argument functions.
terra part1()
  c.ca0()
  t.ta0()

  teq(c.cb1(1), 1)
  teq(t.tb1(1), 1)
  teq(c.cb2(1, 2), 3)
  teq(t.tb2(1, 2), 3)
  teq(c.cb3(1, 2, 3), 6)
  teq(t.tb3(1, 2, 3), 6)
  teq(c.cb4(1, 2, 3, 4), 10)
  teq(t.tb4(1, 2, 3, 4), 10)
  teq(c.cb5(1, 2, 3, 4, 5), 15)
  teq(t.tb5(1, 2, 3, 4, 5), 15)
  teq(c.cb6(1, 2, 3, 4, 5, 6), 21)
  teq(t.tb6(1, 2, 3, 4, 5, 6), 21)
  teq(c.cb7(1, 2, 3, 4, 5, 6, 7), 28)
  teq(t.tb7(1, 2, 3, 4, 5, 6, 7), 28)
  teq(c.cb8(1, 2, 3, 4, 5, 6, 7, 8), 36)
  teq(t.tb8(1, 2, 3, 4, 5, 6, 7, 8), 36)
  teq(c.cb9(1, 2, 3, 4, 5, 6, 7, 8, 9), 45)
  teq(t.tb9(1, 2, 3, 4, 5, 6, 7, 8, 9), 45)

  teq(c.cc1(1), 1)
  teq(t.tc1(1), 1)
  teq(c.cc2(1, 2), 3)
  teq(t.tc2(1, 2), 3)
  teq(c.cc3(1, 2, 3), 6)
  teq(t.tc3(1, 2, 3), 6)
  teq(c.cc4(1, 2, 3, 4), 10)
  teq(t.tc4(1, 2, 3, 4), 10)
  teq(c.cc5(1, 2, 3, 4, 5), 15)
  teq(t.tc5(1, 2, 3, 4, 5), 15)
  teq(c.cc6(1, 2, 3, 4, 5, 6), 21)
  teq(t.tc6(1, 2, 3, 4, 5, 6), 21)
  teq(c.cc7(1, 2, 3, 4, 5, 6, 7), 28)
  teq(t.tc7(1, 2, 3, 4, 5, 6, 7), 28)
  teq(c.cc8(1, 2, 3, 4, 5, 6, 7, 8), 36)
  teq(t.tc8(1, 2, 3, 4, 5, 6, 7, 8), 36)
  teq(c.cc9(1, 2, 3, 4, 5, 6, 7, 8, 9), 45)
  teq(t.tc9(1, 2, 3, 4, 5, 6, 7, 8, 9), 45)

  teq(c.cd1(1), 1)
  teq(t.td1(1), 1)
  teq(c.cd2(10, 2), 12)
  teq(t.td2(10, 2), 12)
  teq(c.cd3(100, 20, 3), 123)
  teq(t.td3(100, 20, 3), 123)
  teq(c.cd4(1000, 200, 30, 4), 1234)
  teq(t.td4(1000, 200, 30, 4), 1234)
  teq(c.cd5(10000, 2000, 300, 40, 5), 12345)
  teq(t.td5(10000, 2000, 300, 40, 5), 12345)
  teq(c.cd6(100000, 20000, 3000, 400, 50, 6), 123456)
  teq(t.td6(100000, 20000, 3000, 400, 50, 6), 123456)
  teq(c.cd7(1000000, 200000, 30000, 4000, 500, 60, 7), 1234567)
  teq(t.td7(1000000, 200000, 30000, 4000, 500, 60, 7), 1234567)
  teq(c.cd8(10000000, 2000000, 300000, 40000, 5000, 600, 70, 8), 12345678)
  teq(t.td8(10000000, 2000000, 300000, 40000, 5000, 600, 70, 8), 12345678)
  teq(c.cd9(100000000, 20000000, 3000000, 400000, 50000, 6000, 700, 80, 9), 123456789)
  teq(t.td9(100000000, 20000000, 3000000, 400000, 50000, 6000, 700, 80, 9), 123456789)

  teq(c.ce1(1), 1)
  teq(t.te1(1), 1)
  teq(c.ce2(10, 2), 12)
  teq(t.te2(10, 2), 12)
  teq(c.ce3(100, 20, 3), 123)
  teq(t.te3(100, 20, 3), 123)
  teq(c.ce4(1000, 200, 30, 4), 1234)
  teq(t.te4(1000, 200, 30, 4), 1234)
  teq(c.ce5(10000, 2000, 300, 40, 5), 12345)
  teq(t.te5(10000, 2000, 300, 40, 5), 12345)
  teq(c.ce6(100000, 20000, 3000, 400, 50, 6), 123456)
  teq(t.te6(100000, 20000, 3000, 400, 50, 6), 123456)
  teq(c.ce7(1000000, 200000, 30000, 4000, 500, 60, 7), 1234567)
  teq(t.te7(1000000, 200000, 30000, 4000, 500, 60, 7), 1234567)
  teq(c.ce8(10000000, 2000000, 300000, 40000, 5000, 600, 70, 8), 12345678)
  teq(t.te8(10000000, 2000000, 300000, 40000, 5000, 600, 70, 8), 12345678)
  teq(c.ce9(100000000, 20000000, 3000000, 400000, 50000, 6000, 700, 80, 9), 123456789)
  teq(t.te9(100000000, 20000000, 3000000, 400000, 50000, 6000, 700, 80, 9), 123456789)

  teq(c.cf1(1), 1)
  teq(t.tf1(1), 1)
  teq(c.cf2(10, 2), 12)
  teq(t.tf2(10, 2), 12)
  teq(c.cf3(100, 20, 3), 123)
  teq(t.tf3(100, 20, 3), 123)
  teq(c.cf4(1000, 200, 30, 4), 1234)
  teq(t.tf4(1000, 200, 30, 4), 1234)
  teq(c.cf5(10000, 2000, 300, 40, 5), 12345)
  teq(t.tf5(10000, 2000, 300, 40, 5), 12345)
  teq(c.cf6(100000, 20000, 3000, 400, 50, 6), 123456)
  teq(t.tf6(100000, 20000, 3000, 400, 50, 6), 123456)
  teq(c.cf7(1000000, 200000, 30000, 4000, 500, 60, 7), 1234567)
  teq(t.tf7(1000000, 200000, 30000, 4000, 500, 60, 7), 1234567)
  teq(c.cf8(10000000, 2000000, 300000, 40000, 5000, 600, 70, 8), 12345678)
  teq(t.tf8(10000000, 2000000, 300000, 40000, 5000, 600, 70, 8), 12345678)
  teq(c.cf9(100000000, 20000000, 3000000, 400000, 50000, 6000, 700, 80, 9), 123456789)
  teq(t.tf9(100000000, 20000000, 3000000, 400000, 50000, 6000, 700, 80, 9), 123456789)

  teq(c.cg1(1), 1)
  teq(t.tg1(1), 1)
  teq(c.cg2(10, 2), 12)
  teq(t.tg2(10, 2), 12)
  teq(c.cg3(100, 20, 3), 123)
  teq(t.tg3(100, 20, 3), 123)
  teq(c.cg4(1000, 200, 30, 4), 1234)
  teq(t.tg4(1000, 200, 30, 4), 1234)
  teq(c.cg5(10000, 2000, 300, 40, 5), 12345)
  teq(t.tg5(10000, 2000, 300, 40, 5), 12345)
  teq(c.cg6(100000, 20000, 3000, 400, 50, 6), 123456)
  teq(t.tg6(100000, 20000, 3000, 400, 50, 6), 123456)
  teq(c.cg7(1000000, 200000, 30000, 4000, 500, 60, 7), 1234567)
  teq(t.tg7(1000000, 200000, 30000, 4000, 500, 60, 7), 1234567)
  teq(c.cg8(10000000, 2000000, 300000, 40000, 5000, 600, 70, 8), 12345678)
  teq(t.tg8(10000000, 2000000, 300000, 40000, 5000, 600, 70, 8), 12345678)
  teq(c.cg9(100000000, 20000000, 3000000, 400000, 50000, 6000, 700, 80, 9), 123456789)
  teq(t.tg9(100000000, 20000000, 3000000, 400000, 50000, 6000, 700, 80, 9), 123456789)

  teq(c.ch1(1), 1)
  teq(t.th1(1), 1)
  teq(c.ch2(1, 2), 3)
  teq(t.th2(1, 2), 3)
  teq(c.ch3(1, 2, 3), 6)
  teq(t.th3(1, 2, 3), 6)
  teq(c.ch4(1, 2, 3, 4), 10)
  teq(t.th4(1, 2, 3, 4), 10)
  teq(c.ch5(1, 2, 3, 4, 5), 15)
  teq(t.th5(1, 2, 3, 4, 5), 15)
  teq(c.ch6(1, 2, 3, 4, 5, 6), 21)
  teq(t.th6(1, 2, 3, 4, 5, 6), 21)
  teq(c.ch7(1, 2, 3, 4, 5, 6, 7), 28)
  teq(t.th7(1, 2, 3, 4, 5, 6, 7), 28)
  teq(c.ch8(1, 2, 3, 4, 5, 6, 7, 8), 36)
  teq(t.th8(1, 2, 3, 4, 5, 6, 7, 8), 36)
  teq(c.ch9(1, 2, 3, 4, 5, 6, 7, 8, 9), 45)
  teq(t.th9(1, 2, 3, 4, 5, 6, 7, 8, 9), 45)

  teq(c.ci1(1), 1)
  teq(t.ti1(1), 1)
  teq(c.ci2(1, 2), 3)
  teq(t.ti2(1, 2), 3)
  teq(c.ci3(1, 2, 3), 6)
  teq(t.ti3(1, 2, 3), 6)
  teq(c.ci4(1, 2, 3, 4), 10)
  teq(t.ti4(1, 2, 3, 4), 10)
  teq(c.ci5(1, 2, 3, 4, 5), 15)
  teq(t.ti5(1, 2, 3, 4, 5), 15)
  teq(c.ci6(1, 2, 3, 4, 5, 6), 21)
  teq(t.ti6(1, 2, 3, 4, 5, 6), 21)
  teq(c.ci7(1, 2, 3, 4, 5, 6, 7), 28)
  teq(t.ti7(1, 2, 3, 4, 5, 6, 7), 28)
  teq(c.ci8(1, 2, 3, 4, 5, 6, 7, 8), 36)
  teq(t.ti8(1, 2, 3, 4, 5, 6, 7, 8), 36)
  teq(c.ci9(1, 2, 3, 4, 5, 6, 7, 8, 9), 45)
  teq(t.ti9(1, 2, 3, 4, 5, 6, 7, 8, 9), 45)

  return 0
end
part1:compile() -- workaround: function at line 620 has more than 60 upvalues
-- part1:printpretty(false)

-- Part 2: check the one-arg aggregate functions.
terra part2()
  var x0 : c.p0
  var cx0 = c.cp0(x0)
  var tx0 = t.tp0(x0)

  escape
    for _, name in ipairs(uniform_names) do
      for N = 1, 9 do
        local aggtyp = c[name .. N]
        local cfunc = c["c" .. name .. N]
        local tfunc = t["t" .. name .. N]
        emit quote
          var x : aggtyp
          init_fields(x, 10, N)
          var cx = cfunc(x)
          check_fields(x, 10, N)
          check_fields(cx, 11, N)
          var tx = tfunc(x)
          check_fields(x, 10, N)
          check_fields(tx, 11, N)
        end
      end
    end
  end

  escape
    for _, name in ipairs(nonuniform_names) do
      for N = 1, 9 do
        local aggtyp = c[name .. N]
        local cfunc = c["c" .. name .. N]
        local tfunc = t["t" .. name .. N]
        emit quote
          var x : aggtyp
          init_fields(x, 10, N)
          var cx = cfunc(x)
          check_fields(x, 10, N)
          check_fields(cx, 11, N)
          var tx = tfunc(x)
          check_fields(x, 10, N)
          check_fields(tx, 11, N)
        end
      end
    end
  end

  return 0
end

terra main()
  var err = part1()
  if err ~= 0 then
    return err
  end

  err = part2()
  if err ~= 0 then
    return err
  end
  return 0
end

-- Useful for debugging:
-- print(terralib.saveobj(nil, "llvmir", {main=main}, nil, nil, false))
test.eq(main(), 0)
