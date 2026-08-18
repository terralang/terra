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
		if e ~= lst[i] then
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

-- The line number of the line in `path` tagged with a marker comment, so that
-- editing a test file cannot silently invalidate the lines it asserts on.
function test.markerline(path, name)
	local tag = "@" .. "@" .. name
	local n = 0
	for line in io.lines(path) do
		n = n + 1
		if line:find(tag, 1, true) then return n end
	end
	error("no line in " .. path .. " is tagged " .. tag, 2)
end

return test
