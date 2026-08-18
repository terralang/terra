-- How the stack is walked, and what reaches the user when it is.
--
-- Terra frames are recovered from the frame pointer chain, which the JIT only
-- keeps under -g because it costs a register in every function. This checks
-- that -g recovers the whole chain from both entry points -- an explicit
-- terralib.traceback and a real fault, which start the walk differently -- and
-- that without -g the traceback says what may be missing rather than quietly
-- printing a shorter stack.
--
-- Line numbers are asserted per frame: an intermediate frame holds a return
-- address, so reporting the call site rather than the statement after it is the
-- part that is easy to get wrong.

local ffi = require("ffi")
local test = require("test")

if not terralib.traceback then
  assert(ffi.arch ~= "x64" and ffi.arch ~= "arm64",
         "the debug interface is missing on " .. ffi.arch .. ", which has closures")
  print("skipping: this build has no debug interface")
  return
end

-- The walk follows the frame pointer chain from RtlCaptureContext().Rbp, but
-- Win64 keeps no such chain: rbp is a general register there and unwinding goes
-- through .pdata instead. Only the innermost frame is recoverable, so there is
-- nothing here to check. See windows-traceback-plan.md.
if ffi.os == "Windows" then
  print("skipping: Win64 keeps no frame pointer chain to walk")
  return
end

local scriptpath = arg[0]
local terracmd = terralib.terrahome .. "/bin/terra"

--------------------------------------------------------------------------------
-- Children. Each chain is three deep with no call in tail position, or there is
-- no chain left to recover.
--------------------------------------------------------------------------------

if arg[1] == "traceback" then
  local terra leaf() : int
    terralib.traceback(nil)      --@@tbleaf
    return 0
  end
  leaf:setinlined(false)
  local terra mid() : int
    return leaf() + 1            --@@tbmid
  end
  mid:setinlined(false)
  local terra top() : int
    return mid() + 1             --@@tbtop
  end
  top:setinlined(false)
  assert(top() == 2)
  return
end

-- The innermost function here makes no call, so it is a leaf and gets no frame
-- record of its own. Recovering its caller is what frame-pointer=all buys.
if arg[1] == "crash" then
  local terra leaf(x : int) : int
    var p = [&int](x)
    return @p                    --@@crleaf
  end
  leaf:setinlined(false)
  local terra mid(x : int) : int
    return leaf(x) + 1           --@@crmid
  end
  mid:setinlined(false)
  local terra top(x : int) : int
    return mid(x) + 1            --@@crtop
  end
  top:setinlined(false)
  top(1)
  return
end

if arg[1] == "overflow" then
  local sink = global(&int, nil)
  local terra recur(x : int) : int
    var pad : int[64]
    pad[0] = x
    sink = &pad[0]               -- the address escapes, so this cannot be a loop
    return recur(x + 1) + pad[0]
  end
  recur:setinlined(false)
  recur(1)
  return
end

--------------------------------------------------------------------------------
-- Parent.
--------------------------------------------------------------------------------

-- Children are read through a pipe, which is also the case that loses output if
-- the handler does not flush before the signal is re-raised.
local function run(flags, mode, wantok)
  local cmd = terracmd .. flags .. " " .. scriptpath .. " " .. mode .. " 2>&1"
  print("Running command: " .. cmd)
  io.stdout:flush()
  local pipe = assert(io.popen(cmd, "r"))
  local out = pipe:read("*a")
  local ok = pipe:close()
  if wantok then assert(ok, "the " .. mode .. " child failed:\n" .. out) end
  return out
end

local function terraframes(out)
  local n = 0
  for _ in out:gmatch("terra %(JIT%)") do n = n + 1 end
  return n
end

local basename = scriptpath:match("([^/\\]*)$"):gsub("[%.%-]", "%%%1")
local function reports(out, marker)
  local line = test.markerline(scriptpath, marker)
  return out:find(basename .. ":" .. line .. "%)") ~= nil, line
end

local function checkchain(out, mode, markers)
  local n = terraframes(out)
  assert(n == #markers,
         mode .. " with -g reported " .. n .. " Terra frames, expected "
         .. #markers .. ":\n" .. out)
  for _, m in ipairs(markers) do
    local found, line = reports(out, m)
    assert(found, mode .. " with -g does not report " .. basename .. ":" .. line
           .. " (@@" .. m .. "):\n" .. out)
  end
end

-- An explicit traceback: the walk starts from the calling frame.
local tb = run(" -g", "traceback", true)
checkchain(tb, "traceback", {"tbleaf", "tbmid", "tbtop"})
assert(not tb:find("may be missing", 1, true),
       "a complete traceback should not claim frames may be missing:\n" .. tb)

-- A fault: the walk starts from the signal context instead, and the innermost
-- frame belongs to a function that never set up a frame record.
local cr = run(" -g", "crash", false)
checkchain(cr, "crash", {"crleaf", "crmid", "crtop"})

-- Without -g there is no chain to follow, so the stack is shorter and says so.
local plain = run("", "traceback", true)
local nplain, nfull = terraframes(plain), terraframes(tb)
assert(nplain < nfull,
       "got " .. nplain .. " Terra frames without -g and " .. nfull
       .. " with it; the frame pointer should only be kept under -g:\n" .. plain)
assert(plain:find("may be missing", 1, true),
       "a shortened traceback does not say how to get the rest:\n" .. plain)

-- A stack overflow has no stack left for the handler, which is why the handler
-- runs on one of its own.
local ov = run(" -g", "overflow", false)
assert(terraframes(ov) > 0, "a stack overflow printed no Terra frames:\n" .. ov)

print("frame walking OK: " .. nfull .. " frames with -g, " .. nplain .. " without")
