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

res,t=make()
assert(res == 13)
local gcd, path = leak.find(t)
if not gcd then
	print(path)
	assert(false)
end