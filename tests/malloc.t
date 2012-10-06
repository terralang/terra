local c = terralib.includecstring [[
	#include <stdlib.h>
	#include <stdio.h>
]]

local N = 10
terra foo()
	c.printf("size = %d\n",sizeof(int):as(int))
	var list = c.malloc(sizeof(int)*N):as(&int)
	for i = 0,N do
		list[i] = i + 1
	end
	var result = 0
	for i = 0,N do
		c.printf("%d = %d\n",i:as(int),list[i])
		result = result + list[i]
	end
	c.free(list:as(&uint8))
	return result
end

local test = require("test")
test.eq(foo(),N*(1 + N)/2)
