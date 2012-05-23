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

return test