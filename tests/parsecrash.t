
local result,err = terralib.loadstring [[
terra result()
    [startXNeeded] = a + strip*L.stripWidth
    [endXNeeded] = 1
end
]]
assert(result == nil)
assert("<string>:3: unexpected ',' or '=' at the beginning of a statement. a ';' may be needed on the previous line. near '='" == err)