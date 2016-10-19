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
function test.meq(a,b)
	local lst = {terralib.unpackstruct(b)}
	if #lst ~= #a then
		error("size mismatch",2)
	end
	for i,e in ipairs(a) do
		local te = lst[i]
		if type(e) == "number" and type(te) == "cdata" then
		    te = tonumber(te)
		end
		if e ~= te then
			error(tostring(i) .. ": "..tostring(e) .. " ~= " .. tostring(lst[i]),2)
		end
	end
end

function test.time(fn)
    local s = os.clock()
    fn()
    local e = os.clock()
    return e - s
end
return test