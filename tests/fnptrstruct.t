local C = terralib.includecstring [[
    struct Foo { int (*what)(int); };
]]

C.Foo:printpretty()

terra bar(a : int) return a + 1 end

terra foo(a : &C.Foo, b : int -> int)
    a.what = b
end

foo:disas()