
local function doit()
    coroutine.yield("7")
end
a = coroutine.create(function()
    doit()
end)

local _,s = coroutine.resume(a)
assert(s == "7")
assert(debug.traceback(a,"hi"):match("doit"))
