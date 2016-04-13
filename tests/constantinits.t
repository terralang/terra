function failit(match,fn)
	local success,msg = xpcall(fn,debug.traceback)
	--print(msg)
	if success then
		error("failed to fail.",2)
	elseif not string.match(msg,match) then
		error("failed wrong: "..msg,2)
	end
end

local struct A {
    a : int
    b : int
    c : int[3]
    d : (&A)[3]
}
local a = `A {3, 4}

local v0 = constant(a)
local v1 = constant(`a.a)

local globalc = global(int)
local globala = global(A)
failit("constant initializer",function()
constant(`[&int](array(1,3,4)))
end)
local v2,v3 = globalc,globala

local caddr = constant(`&globalc)
local v4 = constant(`&globala.c)
local v5 = constant(`&globala.c[0])

local v6 = constant(`[&&opaque](&globala.c))

failit("constant initializer",function()
constant(`globala.c)
end)


failit("constant initializer",function()
constant(`globala.c[0])
end)

local v7 = constant(`int(3.5))

failit("constant initializer",function()
constant(`double(globalc))
end)

local seven = 7
local nineteen = constant(`3 + 4 + 1 + seven + sizeof(int))
assert(19 == nineteen:get())
local v8 = nineteen

failit("constant initializer",function()
constant(`globala.c[globalc])
end)

failit("constant initializer",function()
constant(quote var a = 3 in a + a end)
end)

local v9 = constant(`array(2,4,5,6))

local v10 = constant(`vector(2,4,5,6))

local v11 = constant( `&@&globalc )

local v12 = constant(`{ a = 4 })
local v13 = constant(`v12.a)
assert(v13:get() == 4)

failit("constant initializer",function()
constant(`@&globalc)
end)

constant(`&(&globalc)[0]):get()
failit("constant initializer",function()
constant(`(&globalc)[0])
end)

terra usethem()
    globalc = 4
    globala = A { 5,6, array(7,8,9) }
    v6;
    return v0.b + v1 + v2 + (@v4)[0] + @v5 + v7 + v8 +  v9[0] + v10[1] + @v11
end
assert(18 + 7 + 3 + 19 + 2  + 4 + 4 == usethem())