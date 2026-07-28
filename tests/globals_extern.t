local ffi = require 'ffi'

local cstd = terralib.includecstring [[
#include "stdio.h"
#include "stdlib.h"
]]

-- We're going to define three separate globals, in three separate compilation
-- units. Each one is referenced in the other two. In order to pass, globals
-- need to have public visibility and correctly link with the corresponding
-- extern.

local a = terralib.global(int16, 1, "a")
local b = terralib.global(int32, 2, "b")
local c = terralib.global(int64, 3, "c")

local a_ext = terralib.global(int16, nil, "a", true --[[extern]])
local b_ext = terralib.global(int32, nil, "b", true --[[extern]])
local c_ext = terralib.global(int64, nil, "c", true --[[extern]])

terra f(): int64
  return a + b_ext + c_ext
end

terra g(): int64
  return a_ext + b + c_ext
end

terra h(): int64
  return a_ext + b_ext + c
end

local f_ext = terralib.externfunction("f", {} -> int64)
local g_ext = terralib.externfunction("g", {} -> int64)
local h_ext = terralib.externfunction("h", {} -> int64)

terra check(a : int64, b : int64)
  if a ~= b then
    var stderr = cstd.fdopen(2, "w")
    cstd.fprintf(stderr, "mismatch: %lld vs %lld\n", a, b)
    cstd.fflush(stderr)
    cstd.abort()
  end
end

terra main()
  -- Check we got the correct initializers.
  var sum_f1 = f_ext()
  var sum_g1 = g_ext()
  var sum_h1 = h_ext()

  check(sum_f1, 6)
  check(sum_g1, 6)
  check(sum_h1, 6)

  -- Mutate the values through their externs and make sure we still get the right results.
  a_ext = 100
  b_ext = 200
  c_ext = 300
  var sum_f2 = f_ext()
  var sum_g2 = g_ext()
  var sum_h2 = h_ext()

  check(sum_f2, 600)
  check(sum_g2, 600)
  check(sum_h2, 600)

  return 0
end

local tmp_dir
do
  -- use os.tmpname to get a hopefully-unique directory to work in
  local tmpfile = os.tmpname()
  tmp_dir = tmpfile .. ".d/"
  print("Creating temporary directory " .. tmp_dir)
  if ffi.os == "Windows" then
    assert(os.execute("mkdir \"" .. tmp_dir .. "\"") == 0)
  else
    assert(os.execute("mkdir " .. tmp_dir) == 0)
  end
  -- Hack: keep the tmpfile to be absolutely sure we won't collide
  -- os.remove(tmpfile)
end

-- Run this test twice: once for static and once for dynamic linking.
local exts = terralib.newlist({".o"})
if ffi.os == "OSX" then
  exts:insert(".dylib")
elseif ffi.os == "Windows" then
  exts:insert(".dll")
else
  exts:insert(".so")
end

local bin_ext = ""
if ffi.os == "Windows" then
  bin_ext = ".exe"
end

for _, ext in ipairs(exts) do
  local dynamic = ext ~= ".o"

  print()
  print("Running test for " .. ext)

  local prefix = ""
  if dynamic then
    prefix = "lib"
  end

  local f_obj = tmp_dir .. prefix .. "f" .. ext
  local g_obj = tmp_dir .. prefix .. "g" .. ext
  local h_obj = tmp_dir .. prefix .. "h" .. ext
  local main_obj = tmp_dir .. prefix .. "main" .. ext

  local main_deps = terralib.newlist()
  if dynamic then
    if ffi.os ~= "Windows" then
      main_deps:insert("-Wl,-rpath," .. tmp_dir)
    end
    main_deps:insertall({"-L" .. tmp_dir, "-lf", "-lg", "-lh"})
  end

  terralib.saveobj(f_obj, {f=f})
  terralib.saveobj(g_obj, {g=g})
  terralib.saveobj(h_obj, {h=h})
  terralib.saveobj(main_obj, {main=main}, main_deps)

  local link_deps = terralib.newlist()
  if dynamic then
    if ffi.os ~= "Windows" then
      link_deps:insert("-Wl,-rpath," .. tmp_dir)
    end
    link_deps:insertall({"-L" .. tmp_dir, "-lf", "-lg", "-lh", "-lmain"})
  else
    link_deps:insertall({f_obj, g_obj, h_obj, main_obj})
  end
  local executable = tmp_dir .. "main" .. bin_ext

  terralib.saveobj(executable, "executable", {}, link_deps)

  print("Running command: " .. executable)
  assert(os.execute(executable) == 0)
end
