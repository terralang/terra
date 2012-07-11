
struct B { a : A[4] }
struct A { b : B }

terra foo()
    var a : A    
end
foo()