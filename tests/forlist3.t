
local callcount = 0

struct iter {n: int}

iter.metamethods.__for = function(self, body)
	return quote
		[ body(`self.n) ]
		[ body(`self.n) ]
	end
end

local callinfo = {n=0}
terra this_should_be_called_once(n: int)
	[terralib.cast({} -> {}, function() callinfo.n = callinfo.n + 1 end)]()
	return iter{n}
end

local checkcalls = {n = 0, expect = {5, 5}}
local spy = terralib.cast({int} -> {}, function(val)
        checkcalls.n = checkcalls.n + 1
        assert(checkcalls.expect[checkcalls.n] == val, "spy called with incorrect value")
    end
)

terra test()
	for x in this_should_be_called_once(5) do
		spy(x)
	end
end

test()

assert(checkcalls.n == #checkcalls.expect, "spy called the wrong number of times")
assert(callinfo.n == 1, "body expansion called the wrong number of times.")
