local C = terralib.includecstring [[
    #include <stdio.h>
    #include <stdlib.h>
]]

local ffi = require("ffi")

local S = {}

S.error = macro(function(expr, msg)
    local tree = expr.tree
    local filename = tree.filename
    local linenumber = tree.linenumber
    local offset = tree.offset
    local loc = filename .. ":" .. linenumber .. "+" .. offset
    return quote
        terralib.debuginfo(filename, linenumber)
        C.printf("%s: %s\n", loc, msg)
        C.abort()
    end
end)

S.assert = macro(function(condition)
    return quote
        if not condition then
            S.error(condition, "assertion failed!")
        end
    end
end)

S.printf = C.printf

return S
