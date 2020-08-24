

terra foo(a : int, b : int)
    return a + b
end

local ffi =  require 'ffi'

-- We can run this test concurrently, make sure we don't clobber the other test.
local suffix = ""
if 0 ~= terralib.isdebug then
  suffix = "-debug"
end

local name = (ffi.os == "Windows" and "foo" .. suffix .. ".dll" or "foo" .. suffix .. ".so")

local args = {}

if ffi.os == "Windows" then
	args = {"/IMPLIB:foo.lib","/EXPORT:foo" }
end

terralib.saveobj(name,{ foo = foo }, args)

local foo2 = terralib.externfunction("foo", {int,int} -> int )
terralib.linklibrary("./"..name)

assert(4 == foo2(1,3))
