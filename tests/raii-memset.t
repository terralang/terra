local C = terralib.includecstring [[
   #include <stdio.h>
   #include <string.h>
]]

local test = require("test")
local err = require("lib.utils")

local function printtestheader(s)
    print()
    print("===========================")
    print(s)
    print("===========================")
end

--sanity check to make sure that using memset setting to '0'
--is equal to setting pointers to nil. This is apparently not 
--in the C/C++ statndard, but should be the case on all 
--operating systems that we work on.
terra main()
    var pointers : (&int)[5]
    var x : &int
    C.memset(&pointers, 0, [sizeof(pointers.type)])
    C.memset(&x, 0, [sizeof(x.type)])

    for i=0,5 do
        err.assert(pointers[i] == nil)
    end
    err.assert(x == nil)
end
main()