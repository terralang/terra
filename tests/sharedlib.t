

terra foo(a : int, b : int)
    return a + b
end

terralib.saveobj("foo.so",{ foo = foo })

local foo2 = terralib.externfunction("foo", {int,int} -> int )
terralib.linklibrary("foo.so")

assert(4 == foo2(1,3))