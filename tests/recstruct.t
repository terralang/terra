local c = terralib.includecstring [[
	#include <stdlib.h>
	#include <stdio.h>
]]


struct Node {
	next : &Node;
	v : int;
}

local N = 10
terra foo()
	var NULL : &Node = (0):as(&Node)
	var cur : &Node = NULL
	for i = 0, N do
		var n = c.malloc(sizeof(Node)):as(&Node)
		n.v = i
		n.next = cur
		cur = n
	end
	var sum = 0
	while cur ~= NULL do
		c.printf("%d\n",cur.v)
		sum = sum + cur.v
		var old = cur
		cur = cur.next
		c.free(old)
	end
	return sum
end

local test = require("test")
test.eq(foo(),N * (N - 1) / 2)