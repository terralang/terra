local ffi = require 'ffi'

local cstd = terralib.includecstring [[
#include "stdio.h"
#include "stdlib.h"
]]

-- We're going to define three separate globals, in three separate compilation
-- units. Each one is referenced in subsequent compilation units. In order to
-- pass, globals need to have public visibility and correctly link with the
-- corresponding extern.

local a = terralib.global(int16, 1, "a")
local b = terralib.global(int32, 2, "b")
local c = terralib.global(int64, 3, "c")

local a_ext = terralib.global(int16, nil, "a", true --[[extern]])
local b_ext = terralib.global(int32, nil, "b", true --[[extern]])
local c_ext = terralib.global(int64, nil, "c", true --[[extern]])

terra f(): int64
  return a
end

terra g(): int64
  return a_ext + b
end

terra h(): int64
  return a_ext + b_ext + c
end

local f_ext = terralib.externfunction("f", {} -> int64)
local g_ext = terralib.externfunction("g", {} -> int64)
local h_ext = terralib.externfunction("h", {} -> int64)

terra check(x : int64, y : int64)
  if x ~= y then
    cstd.printf("mismatch: %lld vs %lld\n", x, y)
    cstd.exit(1)
  end
end

terra main()
  -- Check we got the correct initializers.
  var sum_f1 = f_ext()
  var sum_g1 = g_ext()
  var sum_h1 = h_ext()

  check(sum_f1, 1)
  check(sum_g1, 3)
  check(sum_h1, 6)

  -- Mutate the values through their externs and make sure we still get the right results.
  a_ext = 100
  b_ext = 200
  c_ext = 300
  var sum_f2 = f_ext()
  var sum_g2 = g_ext()
  var sum_h2 = h_ext()

  check(sum_f2, 100)
  check(sum_g2, 300)
  check(sum_h2, 600)

  return 0
end

local sep = ffi.os == "Windows" and "\\" or "/"

-- Build everything in a subdirectory of the test directory. Keeping the
-- executable and the shared libraries side by side is what makes the rpath
-- below (and Windows's own DLL search order) find them.
local root_dir = arg[0]:match(".*[/\\\\]") or "." .. sep
local tmp_dir = root_dir .. "globals_extern_tmp"
do
  print("Creating temporary directory " .. tmp_dir)
  if ffi.os == "Windows" then
    assert(os.execute("if not exist " .. tmp_dir .. " mkdir " .. tmp_dir) == 0)
  else
    assert(os.execute("mkdir -p " .. tmp_dir) == 0)
  end
end

-- Run this test twice: once for static and once for dynamic linking.
local exts = terralib.newlist({".o"})
if ffi.os == "OSX" then
  exts:insert(".dylib")
elseif ffi.os == "Windows" then
  -- Skip Windows dynamic linking, which requires dllimport and dllexport.
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

  local f_obj = tmp_dir .. sep .. prefix .. "f" .. ext
  local g_obj = tmp_dir .. sep .. prefix .. "g" .. ext
  local h_obj = tmp_dir .. sep .. prefix .. "h" .. ext
  local main_obj = tmp_dir .. sep .. prefix .. "main" .. ext

  -- Load libraries relative to executable location.
  local origin = ffi.os == "OSX" and "@loader_path" or "$ORIGIN"

  local main_deps = terralib.newlist()
  if dynamic then
    main_deps:insertall({"-Wl,-rpath," .. origin, "-L" .. tmp_dir, "-lf", "-lg", "-lh"})
  end

  terralib.saveobj(f_obj, {f=f})
  terralib.saveobj(g_obj, {g=g})
  terralib.saveobj(h_obj, {h=h})
  terralib.saveobj(main_obj, {main=main}, main_deps)

  local link_deps = terralib.newlist()
  if dynamic then
    link_deps:insertall({"-Wl,-rpath," .. origin, "-L" .. tmp_dir, "-lf", "-lg", "-lh", "-lmain"})
  else
    link_deps:insertall({f_obj, g_obj, h_obj, main_obj})
  end
  local executable = tmp_dir .. sep .. "main" .. bin_ext

  terralib.saveobj(executable, "executable", {}, link_deps)

  print("Running command: " .. executable)
  assert(os.execute(executable) == 0)
end
