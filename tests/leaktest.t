-- Disabled due to non-deterministic failures: https://github.com/zdevito/terra/issues/404
if os.getenv("CI") then
  print("This test does not pass reliably in CI, skipping...")
  return
end

local leak = require "lib.leak"

function make()
  local terra a(x:int)
    return x+1
  end

  local terra b(x:int)
    return a(x)
  end
  
  return b(12),leak.track(b)
end
nan = 0/0
res,t=make()
assert(res == 13)
local gcd, path = leak.find(t)
if gcd then
	print(path)
	assert(false)
end

l = leak.track(leak)
foo = 0/0
local f,p = leak.find(l)
assert(f)
assert(p == "$locals.leak")
