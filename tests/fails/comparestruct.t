struct S {}
terra foo()
    var a : S, b : S
    return a == b
end
foo()
