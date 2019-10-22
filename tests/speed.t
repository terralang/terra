local C = terralib.includecstring [[ 
    #include <stdlib.h>
    #include <stdio.h>
]]

terra doit(N : int64)
    var cur,last = 1ULL,1ULL
    for i = 0ULL, (N-2ULL) do
        cur,last = cur+last,cur
    end
    return cur
end
terra main(argc : int, argv : &&int8)
    var N = 4ULL
    if argc == 2 then
        N = C.atoi(argv[1])
    end
    var result = doit(N)
    C.printf("%lld\n",result)
end

terra what()
	return C.atoi("54")
end

local test = require("test")
print(what())
print(test.time( function() doit:compile() end))
print(test.time( function() doit(100000000) end))
print(test.time( function() terralib.saveobj("speed",{main = main}) end))
