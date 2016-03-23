

terra foo(a : int) return a + 3 end

terra bar(a : int) : int
    if a == 0 then return 0
    else return bar(a - 1) + 1 end
end

foo:resetdefinition(bar)

assert(bar(7) == 7)
assert(foo(5) == 5)


assert(foo:compile() == bar:compile())

bar:disas()