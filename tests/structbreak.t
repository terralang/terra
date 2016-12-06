function failit(fn,match)
	local success,msg = xpcall(fn,debug.traceback)
	match = match or "Errors reported during"
	if success then
		error("failed to fail.",2)
	elseif not string.match(msg,match) then
		error("failed wrong: "..msg,2)
	end
end

struct S {
    a: int
}

failit(function()
    S[4] = 3
end,"cannot be overridden")

failit(function()
    function S:getmethod()
    end
end,"cannot be overridden")

function S:isdefined()
    return true
end

failit(function()

struct S {
    b : int
}
struct S {
    c : int
}
end,"duplicate definition of")

struct A {
    a : int
}

function A:isdefined()
    return false
end

struct A {
    b : int
}

--A:printpretty()

function A:isdefined()
    return true
end

terra what()
    var s = A {1,2}
    return s.a + s.b
end

assert(3 == what())
