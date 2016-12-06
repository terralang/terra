function failit(fn,match)
	local success,msg = xpcall(fn,debug.traceback)
	match = match or "Errors reported during"
	if success then
		error("failed to fail.",2)
	elseif not string.match(msg,match) then
		error("failed wrong: "..msg,2)
	end
end

C = terralib.includecstring [[

    struct Foo {
        int a;
        int b;
    };

]]
function C.Foo:isdefined()
    return false
end


failit(function()

struct C.Foo {
    c : int;
}

end, "attempting to define a completed struct")
