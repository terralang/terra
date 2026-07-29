-- A randomized differential test for the C calling convention.
--
-- Each run builds a batch of C functions with randomly shaped signatures --
-- scalars and aggregates interleaved, with and without a struct return -- and
-- then calls each one from Terra and checks the answer. Terra and Clang have to
-- agree about which arguments travel in registers and which are passed on the
-- stack; where they disagree, the callee reads the wrong slots and the result
-- comes out wrong.
--
-- This complements the other two calling convention tests. cconv.t is a fixed
-- list of hand-picked corner cases and cconv_more.t is a systematic sweep over
-- argument counts and types, but both only ever vary one thing at a time. What
-- historically broke is the interleavings: mixed sequences where one register
-- file runs out well before the other, and where an argument that spilled to
-- the stack must not consume a register that a later argument still needs.
-- See https://github.com/terralang/terra/issues/576.
--
-- Roughly a third of the signatures are also exercised in the opposite
-- direction, with C calling a Terra function, which checks how Terra *defines*
-- such a function rather than only how it calls one.

-- Tuning. NUM_FUNCTIONS is chosen to keep the test to a minute or two; raise it,
-- or change SEED, to search harder when working on the calling convention.
local MAX_N = 14        -- longest argument list to generate
local NUM_FUNCTIONS = 7000
local SEED = 1

-- The batch has to come out identical on every platform and every Lua version,
-- so use an explicit PRNG (MINSTD) rather than math.random, whose sequence is
-- not guaranteed to be reproducible. All products stay under 2^53, so the
-- arithmetic is exact in a double.
assert(SEED >= 1 and SEED < 2147483647, "seed must be in [1, 2^31-1)")
local rand_state = SEED
local function rand(n)
  rand_state = (rand_state * 16807) % 2147483647
  return rand_state % n + 1
end

local scalar_types = {
  {c = "int8_t", t = int8},
  {c = "int16_t", t = int16},
  {c = "int32_t", t = int32},
  {c = "int64_t", t = int64},
  {c = "float", t = float},
  {c = "double", t = double},
}

-- Fields are described structurally rather than as C source, so that the C
-- declaration, the C accessor expressions and the Terra accessor expressions can
-- all be generated from one description and cannot drift apart.
local function fld(name, ctype) return {name = name, ctype = ctype} end
local function arr(name, ctype, n) return {name = name, ctype = ctype, n = n} end
local function sub(name, ctype, fields)
  return {name = name, ctype = ctype, fields = fields}
end

-- A nested struct, to cover aggregates that need a recursive walk to classify.
local nested_decl = "typedef struct NPair { int32_t x; int32_t y; } NPair;"
local nested_fields = {fld("x", "int32_t"), fld("y", "int32_t")}

-- Shapes spanning the classifications that matter on x86-64: one eightbyte and
-- two, INTEGER and SSE and mixed, sizes that are not a whole eightbyte, arrays
-- and nested structs, and some too large for registers at all.
local agg_types = {
  {name = "A1", fields = {fld("a", "uint8_t")}},
  {name = "A2", fields = {fld("a", "uint8_t"), fld("b", "uint8_t"), fld("c", "uint8_t")}},
  {name = "A3", fields = {fld("a", "int16_t")}},
  {name = "A4", fields = {fld("a", "int32_t"), fld("b", "int32_t")}},
  {name = "A5", fields = {fld("a", "int64_t")}},
  {name = "A6", fields = {fld("a", "int64_t"), fld("b", "int64_t")}},
  {name = "A7", fields = {fld("a", "int64_t"), fld("b", "int64_t"), fld("c", "int64_t")}},
  {name = "A8", fields = {fld("a", "float")}},
  {name = "A9", fields = {fld("a", "float"), fld("b", "float")}},
  {name = "A10", fields = {fld("a", "float"), fld("b", "float"), fld("c", "float")}},
  {name = "A11", fields = {arr("a", "float", 4)}},
  {name = "A12", fields = {fld("a", "double")}},
  {name = "A13", fields = {fld("a", "double"), fld("b", "double")}},
  {name = "A14", fields = {arr("a", "double", 3)}},
  {name = "A15", fields = {fld("a", "int32_t"), fld("b", "float")}},
  {name = "A16", fields = {fld("a", "double"), fld("b", "int64_t")}},
  {name = "A17", fields = {fld("a", "int8_t"), fld("b", "double")}},
  {name = "A18", fields = {fld("a", "float"), fld("b", "int64_t")}},
  {name = "A19", fields = {fld("a", "int32_t"), fld("b", "double"), fld("c", "double")}},
  {name = "A20", fields = {arr("a", "uint8_t", 3)}},
  {name = "A21", fields = {arr("a", "float", 2)}},
  {name = "A22", fields = {arr("a", "double", 2), fld("b", "int32_t")}},
  {name = "A23", fields = {sub("a", "NPair", nested_fields), fld("b", "float")}},
  {name = "A24", fields = {fld("a", "int8_t"), sub("b", "NPair", nested_fields)}},
}

-- Values are kept small so they fit every scalar type down to int8, and the
-- weights are the slot numbers, so a dropped, duplicated or reordered argument
-- all change the sum. Two slots would have to be 100 apart to collide, which
-- cannot happen at these argument counts.
local function slot_value(k) return (k - 1) % 100 + 1 end

local function decl_field(f, out)
  if f.n then
    out:insert(f.ctype .. " " .. f.name .. "[" .. f.n .. "];")
  else
    out:insert(f.ctype .. " " .. f.name .. ";")
  end
end

-- Accessor suffixes for every scalar slot in a shape, in declaration order.
local function paths_of(fields, prefix, out)
  for _, f in ipairs(fields) do
    if f.fields then
      paths_of(f.fields, prefix .. "." .. f.name, out)
    elseif f.n then
      for i = 0, f.n - 1 do
        out:insert(prefix .. "." .. f.name .. "[" .. i .. "]")
      end
    else
      out:insert(prefix .. "." .. f.name)
    end
  end
  return out
end

for _, agg in ipairs(agg_types) do
  agg.paths = paths_of(agg.fields, "", terralib.newlist())
end

-- Pick every signature up front, so the C source and the Terra side are built
-- from exactly the same description.
local sigs = terralib.newlist()
for i = 1, NUM_FUNCTIONS do
  local args = terralib.newlist()
  for _ = 1, rand(MAX_N) do
    if rand(100) <= 45 then
      args:insert({kind = "scalar", info = scalar_types[rand(#scalar_types)]})
    else
      args:insert({kind = "agg", info = agg_types[rand(#agg_types)]})
    end
  end
  -- Half return a struct too big for registers, which puts a hidden pointer in
  -- the first integer register and shifts everything that follows.
  local sret = rand(2) == 1
  sigs:insert({
    name = "fn" .. i,
    args = args,
    sret = sret,
    -- Only the plain-double signatures are run in reverse, to keep the C side
    -- simple; the sret ones are already covered in the forward direction.
    reverse = not sret and rand(3) == 1,
  })
end

-- Scalar slots of one signature, as {weight, accessor} against argument names
-- x1, x2, ... The weight is just the slot number.
local function slots_of(sig)
  local out = terralib.newlist()
  for i, arg in ipairs(sig.args) do
    if arg.kind == "scalar" then
      out:insert({w = #out + 1, expr = "x" .. i})
    else
      for _, p in ipairs(arg.info.paths) do
        out:insert({w = #out + 1, expr = "x" .. i .. p})
      end
    end
  end
  return out
end

local function params_of(sig)
  local out = terralib.newlist()
  for i, arg in ipairs(sig.args) do
    out:insert((arg.kind == "scalar" and arg.info.c or arg.info.name) .. " x" .. i)
  end
  return out
end

local function expected_of(sig)
  local total = 0
  for _, s in ipairs(slots_of(sig)) do total = total + s.w * slot_value(s.w) end
  return total
end

local defs = terralib.newlist({"#include <stdint.h>", "", nested_decl})
for _, agg in ipairs(agg_types) do
  local parts = terralib.newlist({"typedef struct " .. agg.name .. " {"})
  for _, f in ipairs(agg.fields) do decl_field(f, parts) end
  parts:insert("} " .. agg.name .. ";")
  defs:insert(parts:concat(" "))
end
defs:insert("typedef struct BigRet { int64_t a, b, c, d; } BigRet;")
defs:insert("")

for _, sig in ipairs(sigs) do
  local sums = terralib.newlist()
  for _, s in ipairs(slots_of(sig)) do
    sums:insert(s.w .. "*(double)" .. s.expr)
  end
  local sum = #sums > 0 and sums:concat(" + ") or "0"
  local params = params_of(sig):concat(", ")
  if sig.sret then
    -- Spread the answer over all four fields so a botched sret shows up.
    defs:insert("__attribute__ ((noinline)) BigRet " .. sig.name .. "(" .. params ..
                ") { double t = " .. sum .. "; BigRet r; r.a = (int64_t)t;" ..
                " r.b = 2*(int64_t)t; r.c = 3*(int64_t)t; r.d = 4*(int64_t)t;" ..
                " return r; }")
  else
    defs:insert("__attribute__ ((noinline)) double " .. sig.name .. "(" .. params ..
                ") { return " .. sum .. "; }")
  end
  if sig.reverse then
    -- The wrapper takes the same arguments and forwards them, so one function
    -- covers both directions: Terra calls it, and it calls back into Terra.
    local types, names = terralib.newlist(), terralib.newlist()
    for i, arg in ipairs(sig.args) do
      types:insert(arg.kind == "scalar" and arg.info.c or arg.info.name)
      names:insert("x" .. i)
    end
    defs:insert("typedef double (*" .. sig.name .. "_t)(" ..
                (#types > 0 and types:concat(", ") or "void") .. ");")
    defs:insert("__attribute__ ((noinline)) double call_" .. sig.name .. "(" ..
                sig.name .. "_t f" .. (#params > 0 and ", " .. params or "") ..
                ") { return f(" .. names:concat(", ") .. "); }")
  end
end

local c = terralib.includecstring(defs:concat("\n"))

-- Terra-side accessor for one scalar slot of an argument.
local function terra_slots(sig, syms)
  local out = terralib.newlist()
  local function walk(expr, fields)
    for _, f in ipairs(fields) do
      if f.fields then
        walk(`expr.[f.name], f.fields)
      elseif f.n then
        for i = 0, f.n - 1 do
          out:insert(`expr.[f.name][i])
        end
      else
        out:insert(`expr.[f.name])
      end
    end
  end
  for i, arg in ipairs(sig.args) do
    if arg.kind == "scalar" then
      out:insert(`[syms[i]])
    else
      walk(`[syms[i]], arg.info.fields)
    end
  end
  return out
end

local function weighted_sum(exprs)
  local total = `0.0
  for i, e in ipairs(exprs) do
    total = `total + [double](i) * [double](e)
  end
  return total
end

-- Build the argument values for a call: every scalar slot gets its own value.
local function build_args(sig)
  local stats, argvals = terralib.newlist(), terralib.newlist()
  local k = 0
  for i, arg in ipairs(sig.args) do
    if arg.kind == "scalar" then
      k = k + 1
      argvals:insert(`[arg.info.t]([slot_value(k)]))
    else
      local sym = terralib.newsymbol(c[arg.info.name], "x" .. i)
      stats:insert(quote var [sym] end)
      local function walk(expr, fields)
        for _, f in ipairs(fields) do
          if f.fields then
            walk(`expr.[f.name], f.fields)
          elseif f.n then
            for j = 0, f.n - 1 do
              k = k + 1
              stats:insert(quote expr.[f.name][j] = [slot_value(k)] end)
            end
          else
            k = k + 1
            stats:insert(quote expr.[f.name] = [slot_value(k)] end)
          end
        end
      end
      walk(`[sym], arg.info.fields)
      argvals:insert(sym)
    end
  end
  return stats, argvals
end

local failures = 0
local checked = 0

local function report(sig, direction, got, want)
  failures = failures + 1
  local desc = terralib.newlist()
  for _, arg in ipairs(sig.args) do
    desc:insert(arg.kind == "scalar" and arg.info.c or arg.info.name)
  end
  print(string.format("FAIL %s (%s, sret=%s): got %s, expected %s\n  args: %s",
                      sig.name, direction, tostring(sig.sret), tostring(got),
                      tostring(want), desc:concat(", ")))
end

for _, sig in ipairs(sigs) do
  local cfunc = c[sig.name]
  local stats, argvals = build_args(sig)
  local want = expected_of(sig)

  local forward
  if sig.sret then
    forward = terra() : double
      [stats]
      var r = cfunc([argvals])
      return [double](r.a + r.b + r.c + r.d)
    end
    want = 10 * want  -- the four fields hold t, 2t, 3t and 4t
  else
    forward = terra() : double
      [stats]
      return cfunc([argvals])
    end
  end

  checked = checked + 1
  local got = forward()
  if got ~= want then report(sig, "Terra calls C", got, want) end

  if sig.reverse then
    local syms = terralib.newlist()
    for i, arg in ipairs(sig.args) do
      local typ = arg.kind == "scalar" and arg.info.t or c[arg.info.name]
      syms:insert(terralib.newsymbol(typ, "x" .. i))
    end
    local terra callee([syms]) : double
      return [weighted_sum(terra_slots(sig, syms))]
    end
    callee:setinlined(false)

    local wrapper = c["call_" .. sig.name]
    local stats2, argvals2 = build_args(sig)
    local terra reverse() : double
      [stats2]
      return wrapper(callee, [argvals2])
    end

    checked = checked + 1
    local got2 = reverse()
    if got2 ~= want then report(sig, "C calls Terra", got2, want) end
  end
end

print(string.format("cconv_fuzz: %d checks over %d signatures (seed %d, max %d args)",
                    checked, #sigs, SEED, MAX_N))
if failures > 0 then
  error(string.format("%d of %d calling convention checks failed", failures, checked))
end
