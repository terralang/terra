
struct A { a : int }

terra A:foo()
    self.a = self.a + 1
end

terra doit()
    var a = A { 0 }
    defer a:foo()
    defer A.foo(&a)
end

doit:printpretty()