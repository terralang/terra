
struct B { a : A[4] } and
struct A { b : B }

terra foo()
    var a : A
end
foo()
