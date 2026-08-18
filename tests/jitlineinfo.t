-- Test that Terra can map an address inside a JIT compiled function back to
-- the source line it came from.
--
-- This is the lookup behind terralib.lookupline, and behind the file:line that
-- terralib.traceback prints for each Terra frame. It reads the DWARF the JIT
-- emitted, so it needs debug info, and relaunches itself with -g to get it.
-- Which frames a traceback finds in the first place is traceframes.t.

local ffi = require("ffi")
local test = require("test")

-- Built without the debug interface: it needs a hand written closure for the
-- host architecture, and only x86-64 and AArch64 have one. Those two are also
-- the ones where the closures failing to install would be a bug rather than a
-- missing port, and installing them can fail at runtime: a page cannot be
-- written and executed at once on Apple Silicon.
if not terralib.traceback then
  assert(ffi.arch ~= "x64" and ffi.arch ~= "arm64",
         "the debug interface is missing on " .. ffi.arch .. ", which has closures")
  print("skipping: this build has no debug interface")
  return
end


local scriptpath = arg[0]
local terracmd = terralib.terrahome .. "/bin/terra"

-- Flush before every child: stdout is block buffered when it is not a terminal,
-- so without this the parent's output reaches a CI log after the children's.
if terralib.isdebug == 0 then
  -- This pass has no debug info, so the symbol still has to resolve and the
  -- line has to come back missing rather than wrong.
  local terra target(x : int) : int return x * 2 + 1 end
  target:setinlined(false)
  target:compile()
  terra lookup(addr : &opaque) : int
    var si : terralib.SymbolInfo
    var li : terralib.LineInfo
    if not terralib.lookupsymbol(addr, &si) then return -1 end
    if not terralib.lookupline(si.addr, addr, &li) then return 0 end
    return 1
  end
  local got = lookup(target:getpointer())
  assert(got ~= -1, "lookupsymbol failed without -g, where it should still work")
  assert(got == 0, "lookupline returned a line without -g, where there is no line table")

  local cmd = terracmd .. " -g " .. scriptpath
  print("Running command: " .. cmd)
  io.stdout:flush()
  assert(os.execute(cmd) == 0, "failed: " .. cmd)
  return
end

local c = terralib.includec("stdio.h")

--------------------------------------------------------------------------------
-- The function under test.
--------------------------------------------------------------------------------

-- Lines the test cares about are tagged with a marker comment and looked up by
-- name, so that editing this file cannot silently invalidate them. Each
-- statement uses the previous one's result so the optimizer cannot drop any of
-- them, and fflush is a call it cannot fold away, so the function keeps a
-- prologue and a call site rather than compiling to three instructions.

terra work(a : int, b : int) : int
  var x = a * b                --@@first
  var y = x + a
  var z = y - b
  c.fflush(nil)                    --@@call
  return z                     --@@last
end
work:setinlined(false)
work:compile()

local function markerline(name) return test.markerline(scriptpath, name) end

local firstline, lastline = markerline("first"), markerline("last")
local callline = markerline("call")

--------------------------------------------------------------------------------
-- Walk the compiled function and ask for the line behind each address.
--------------------------------------------------------------------------------

local file = terralib.new(rawstring[1])
local filelen = terralib.new(uint64[1])
local lineno = terralib.new(uint64[1])
local fnsize = terralib.new(uint64[1])

-- Returns the size of the function containing addr, or 0 if there is none.
terra symbolsize(addr : &opaque, size : &uint64) : bool
  var si : terralib.SymbolInfo
  if not terralib.lookupsymbol(addr, &si) then return false end
  @size = si.size
  return true
end

-- Returns 0 for an address the line table does not attribute to any statement
-- and 1 otherwise.
terra probe(addr : &opaque, file : &rawstring, filelen : &uint64, lineno : &uint64) : int
  var si : terralib.SymbolInfo
  var li : terralib.LineInfo
  if not terralib.lookupsymbol(addr, &si) then return 0 end
  if not terralib.lookupline(si.addr, addr, &li) then return 0 end
  @file = li.name
  @filelen = li.namelength
  @lineno = li.linenum
  return 1
end

local base = terralib.cast(rawstring, work:getpointer())

-- Walk exactly work(), not until the lookup runs out: any Terra function is a
-- valid answer from lookupsymbol, so an unbounded walk would wander into
-- whatever the JIT placed next and report its lines as work()'s.
assert(symbolsize(base, fnsize), "lookupsymbol did not find the JIT compiled work()")
local size = tonumber(fnsize[0])
assert(size > 0, "work() has zero size")

local lines, files = {}, {}
for i = 0, size - 1 do
  if probe(base + i, file, filelen, lineno) == 1 then
    lines[i] = tonumber(lineno[0])
    files[ffi.string(file[0], tonumber(filelen[0]))] = true
  end
end

local located = 0
for _ in pairs(lines) do located = located + 1 end

-- Reading the line table takes either a copy of the emitted object with its
-- debug sections relocated to where the code was loaded, which RuntimeDyld
-- only builds for ELF, or the object's own sections read as emitted and
-- addresses biased by where the code landed, which is what MachO needs. A
-- platform with neither has nothing to read and nothing to check.
if located == 0 then
  assert(ffi.os ~= "Linux" and ffi.os ~= "BSD" and ffi.os ~= "OSX",
         "no address in work() has line info, out of " .. size .. " bytes")
  print("skipping: " .. ffi.os .. " JIT objects carry no usable debug info")
  return
end

-- Every line reported has to be a statement of work(). What order they come out
-- in as the address grows is up to the instruction scheduler, so don't ask.
local distinct = {}
local ndistinct = 0
for i = 0, size - 1 do
  local line = lines[i]
  if line then
    assert(line >= firstline and line <= lastline,
           "address " .. i .. " into work() reports line " .. line
           .. ", outside the function body (" .. firstline .. ".." .. lastline .. ")")
    if not distinct[line] then
      distinct[line] = true
      ndistinct = ndistinct + 1
    end
  end
end

-- More than one line has to come back, or the lookup could be returning the
-- same answer for every address in the function and still land in range.
assert(ndistinct > 1,
       "every address in work() reports the same line, " .. next(distinct))

-- The call is the one statement whose address is certain to survive
-- optimization, so require it by name rather than trusting the count above.
assert(distinct[callline],
       "no address in work() reports the call on line " .. callline)

-- The file has to be this one, and has to be openable: terralib.traceback
-- prints the source line, so a name that no longer resolves is a bug even
-- though the line number is right.
local seen = 0
for name in pairs(files) do
  seen = seen + 1
  assert(name:match("([^/\\]*)$") == scriptpath:match("([^/\\]*)$"),
         "work() is attributed to " .. name .. " rather than to " .. scriptpath)
  local handle = io.open(name)
  assert(handle, "the reported path " .. name .. " cannot be opened")
  handle:close()
end
assert(seen == 1, "work() is attributed to " .. seen .. " different files")

print("line info OK: " .. located .. " of " .. size .. " bytes of work(), "
      .. ndistinct .. " distinct lines")
