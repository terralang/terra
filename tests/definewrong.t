local r,s = xpcall(function()
local terra a :: int -> int
do end
terra a() end
end,debug.traceback)

assert(not r and s:match "attempting to define terra function declaration with type")