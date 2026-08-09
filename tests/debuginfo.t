-- Test that Terra's debug info survives all the way to a debugger.
--
-- Debug info can only be turned on when the interpreter starts, so this test
-- relaunches itself: once with -g (which records file names as they were
-- spelled on the command line) and once with -g -g (which additionally makes
-- Terra resolve them to absolute paths). Each child builds a small program
-- with a known call stack and then checks
--
--   * the debug metadata Terra attached to the LLVM module (every platform),
--   * the backtrace a debugger prints when the compiled program crashes, and
--   * the backtrace it prints when the same code crashes in the JIT,
--
-- doing the last two whenever gdb or lldb is installed, except on Windows.
-- Both have been checked against gdb 9.2 through 17.1 and lldb 18 on Linux.
--
-- The point of the debugger half is to catch regressions the metadata check
-- cannot see: debug info that is well-formed but never reaches the DWARF of
-- the linked executable, or never reaches the debugger from the JIT.

local ffi = require("ffi")

local debuglevel = terralib.isdebug

local sep = ffi.os == "Windows" and "\\" or "/"
local scriptpath = arg[0]
local scriptdir = scriptpath:match("^(.*[/\\])") or ("." .. sep)
local scriptname = scriptpath:match("([^/\\]*)$")
local terracmd = terralib.terrahome .. "/bin/terra"

-- Escape a literal string for use inside a Lua pattern.
local function patescape(s)
  return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%?%-]", "%%%1"))
end

--------------------------------------------------------------------------------
-- Parent process: relaunch under -g and under -g -g.
--------------------------------------------------------------------------------

if debuglevel == 0 then
  local prefix = terracmd
  if ffi.os == "Windows" then
    prefix = prefix:gsub("[/\\]", "\\\\")
  end
  for _, flags in ipairs({"-g", "-g -g"}) do
    local args = " " .. flags .. " " .. scriptpath
    local cmd
    if ffi.os == "Windows" then
      -- Both the program and the command as a whole need quoting, in case the
      -- path to Terra contains a space.
      cmd = [[cmd /c ""]] .. prefix .. "\"" .. args .. "\""
    else
      cmd = prefix .. args
    end
    print("Running command: " .. cmd)
    assert(os.execute(cmd) == 0, "failed: " .. cmd)
  end
  return
end

--------------------------------------------------------------------------------
-- The program under test.
--------------------------------------------------------------------------------

-- Statements whose line numbers the test cares about are tagged with a marker
-- comment and looked up by name, so that editing this file cannot silently
-- invalidate the expected values.
local function markerline(name)
  local tag = "@" .. "@" .. name
  local n = 0
  for line in io.lines(scriptpath) do
    n = n + 1
    if line:find(tag, 1, true) then return n end
  end
  error("no line in " .. scriptpath .. " is tagged " .. tag)
end

-- A file that does not exist, to check that terralib.debuginfo overrides both
-- the file and the line, and that -g -g leaves it alone rather than resolving
-- it against the working directory.
local customfile = "terra-debuginfo-custom-file.txt"
local customline = 4242

-- Kept in sync by hand with the string level3 prints below: writing it out as
-- a literal there keeps that printf anchored to this file, whereas splicing in
-- a Lua value would attribute the statement to terralib.lua.
local marker = "terra debuginfo test running"

local c = terralib.includecstring [[
#include <stdio.h>
#include <stdlib.h>
]]

-- Each function below gets its argument from its caller rather than from a
-- constant, so that the optimizer cannot fold the call chain away, and none of
-- the calls is in tail position, so every one of them gets a frame of its own.

terra level3(x : int) : int
  c.printf("terra debuginfo test running\n")
  c.fflush([&c.FILE](0))
  if x > 0 then
    c.abort() --@@crash
  end
  return x
end
level3:setinlined(false)

terra level2(x : int) : int
  terralib.debuginfo(customfile, customline)
  return level3(x) + 1
end
level2:setinlined(false)

terra level1(x : int) : int
  var y = level2(x) + 2 --@@call2
  return y
end
level1:setinlined(false)

terra debugmain(argc : int, argv : &rawstring) : int
  var y = level1(argc) --@@call1
  return y + 3
end

-- How Terra records the name of this file: -g keeps the path as it was spelled
-- on the command line, -g -g splits it into a base name plus a directory.
local sourcefile = debuglevel > 1 and scriptname or scriptpath

-- Innermost frame first. Each entry is the Terra function name that should be
-- reported, the file the frame should be attributed to, and the line.
local frames = {
  {"$level3", sourcefile, markerline("crash")},
  {"$level2", customfile, customline},
  {"$level1", sourcefile, markerline("call2")},
  {"$debugmain", sourcefile, markerline("call1")},
}

-- Relaunched by the JIT check below: just crash, so that the debugger running
-- this process has a Terra stack to walk. Everything above this point is JIT
-- compiled, so the same frames should show up minus the one belonging to
-- debugmain, which only the compiled program calls.
if arg[1] == "jit" then
  level1(1)
  error("level1 was supposed to abort")
end

--------------------------------------------------------------------------------
-- Check the debug metadata Terra attached to the module.
--------------------------------------------------------------------------------

local ir = terralib.saveobj(nil, "llvmir", {main = debugmain})

local function irassert(pattern, what)
  if not ir:find(pattern) then
    print(ir)
    error("LLVM IR is missing " .. what .. " (pattern: " .. pattern .. ")")
  end
end

for _, frame in ipairs(frames) do
  local name, file, line = frame[1], frame[2], frame[3]
  irassert('DISubprogram%(name: "' .. patescape(name) .. '"', "a subprogram for " .. name)
  irassert('DIFile%(filename: "' .. patescape(file) .. '"', "a file entry for " .. file)
  irassert("DILocation%(line: " .. line .. ",", "a location on line " .. line)
end

-- Only -g -g pays for resolving the file to an absolute directory.
do
  local directory = ir:match('DIFile%(filename: "' .. patescape(sourcefile)
                             .. '", directory: "([^"]*)"')
  assert(directory, "no DIFile for " .. sourcefile .. " in the module's debug info")
  if debuglevel > 1 then
    assert(directory ~= "." and directory ~= "",
           "-g -g should record an absolute directory, got " .. directory)
  else
    assert(directory == ".",
           "-g should record the file name as spelled, got directory " .. directory)
  end
end

-- terralib.debuginfo names a file that does not exist, so it stays as written
-- even under -g -g.
assert(ir:find('DIFile%(filename: "' .. patescape(customfile) .. '", directory: "%."'),
       "terralib.debuginfo should record " .. customfile .. " verbatim")

print("debug metadata OK (-g level " .. debuglevel .. ")")

--------------------------------------------------------------------------------
-- Pick a debugger.
--------------------------------------------------------------------------------

if ffi.os == "Windows" then
  print("skipping the debugger checks: not supported on Windows")
  return
end

local function hasprogram(name)
  return os.execute(name .. " --version >/dev/null 2>&1") == 0
end

-- gdb and lldb both print one line per frame mentioning the function name and
-- "at <file>:<line>"; that is all this test relies on.
local debuggercmd
if hasprogram("gdb") then
  debuggercmd = function(program)
    return "gdb -batch -nx -ex run -ex bt --args " .. program .. " 2>&1"
  end
elseif hasprogram("lldb") then
  debuggercmd = function(program)
    -- Once the program stops on a signal, lldb's batch mode runs the -k
    -- commands instead of the rest of the -o commands. Pass a backtrace to
    -- both, so that either way we get one and lldb still exits. auto-confirm
    -- keeps quit from asking about killing the stopped process, and leaving
    -- ASLR alone avoids a personality() call that a container running under
    -- the default seccomp profile is not allowed to make.
    return "lldb --batch --no-lldbinit"
           .. " -O 'settings set auto-confirm true'"
           .. " -O 'settings set target.disable-aslr false'"
           .. " -o run -o bt -o quit -k bt -k quit -- " .. program .. " 2>&1"
  end
else
  print("skipping the debugger checks: neither gdb nor lldb is installed")
  return
end

-- Run a program under the debugger and return its combined output, or nil if
-- the debugger could not get the program running at all. That happens where
-- ptrace is unavailable, e.g. in a container that was not given SYS_PTRACE,
-- and is an environment problem rather than a debug info problem.
local function backtraceof(program)
  local cmd = debuggercmd(program)
  print("Running command: " .. cmd)
  local pipe = assert(io.popen(cmd, "r"))
  local output = pipe:read("*a")
  pipe:close()
  if not output:find(marker, 1, true) then
    print(output)
    return nil
  end
  return output
end

-- Check that the debugger reported each of the expected frames, in order,
-- with the right file and line.
local function checkframes(output, expected, what)
  local lines = terralib.newlist()
  for line in output:gmatch("[^\n]+") do
    lines:insert(line)
  end
  local previous = 0
  for _, frame in ipairs(expected) do
    local name, file, line = frame[1], frame[2], frame[3]
    -- Compare base names, since how much of the path a debugger prints varies.
    -- Match "<file>:<line>" but not "<file>:<line>7": lldb appends a column.
    local where = patescape(file:match("([^/\\]*)$")) .. ":" .. line .. "%f[%D]"
    local found
    for i = previous + 1, #lines do
      if lines[i]:find(name, 1, true) and lines[i]:find(where) then
        found = i
        break
      end
    end
    if not found then
      print(output)
      error(what .. ": no frame for " .. name .. " at " .. file .. ":" .. line
            .. " below the previous frame of the backtrace")
    end
    previous = found
  end
  print(what .. " OK (-g level " .. debuglevel .. ")")
end

--------------------------------------------------------------------------------
-- Check the backtrace of a compiled program.
--------------------------------------------------------------------------------

local tmpdir = scriptdir .. "debuginfo_tmp"
assert(os.execute("mkdir -p " .. tmpdir) == 0, "could not create " .. tmpdir)

-- Keep the object file next to the executable: on macOS the DWARF stays in the
-- object file and the executable only points at it, so a debugger can resolve
-- line numbers only while that file is still where the linker found it.
local program = tmpdir .. sep .. "debuginfo_g" .. debuglevel
local object = program .. ".o"
terralib.saveobj(object, "object", {main = debugmain})
terralib.saveobj(program, "executable", {}, {object})

local output = backtraceof(program)
if not output then
  print("skipping the debugger checks: the debugger could not run the program")
  return
end
checkframes(output, frames, "compiled backtrace")

--------------------------------------------------------------------------------
-- Check the backtrace of the same code running in the JIT.
--------------------------------------------------------------------------------

local flags = debuglevel > 1 and "-g -g" or "-g"
output = backtraceof(terracmd .. " " .. flags .. " " .. scriptpath .. " jit")
if not output then
  print("skipping the JIT backtrace check: the debugger could not run the program")
  return
end

-- Reading JIT-compiled code takes support for the interface LLVM registers
-- with __jit_debug_register_code. gdb and lldb both have it on Linux, but a
-- debugger without it cannot see these frames at all, whereas one that has it
-- would still name them even if their debug info were broken. So treat a
-- backtrace with no Terra frames whatsoever as an unsupported debugger rather
-- than as a failure.
if not output:find("$level3", 1, true) then
  print(output)
  print("skipping the JIT backtrace check: this debugger does not report "
        .. "JIT-compiled frames")
  return
end

-- debugmain is never called in the JIT, so its frame is not expected here.
local jitframes = {frames[1], frames[2], frames[3]}
checkframes(output, jitframes, "JIT backtrace")
