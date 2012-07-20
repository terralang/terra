local test = {}

function test.eq(a,b)
	if a ~= b then
		error(tostring(a) .. " ~= "  .. tostring(b),2)
	end
end
function test.neq(a,b)
	if a == b then
		error(tostring(a) .. " == "  .. tostring(b),2)
	end
end

function test.time(fn)
    local s = os.clock()
    fn()
    local e = os.clock()
    return e - s
end
return test